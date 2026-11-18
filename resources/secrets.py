#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "secretstorage==3.3.3",
# ]
# ///
#

"""Improved, non-drop-in secret-tool(1) replacement for the freedesktop Secret Service; run with -h for usage."""

import argparse
import base64
import csv
import getpass
import io
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import textwrap
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone

import secretstorage
from secretstorage.collection import Collection
from secretstorage.exceptions import ItemNotFoundException, SecretStorageException
from secretstorage.item import Item


PROG = os.path.basename(sys.argv[0]) or 'secrets'
EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2
ENV_NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
FORMATS = ('text', 'table', 'json', 'hcl', 'md', 'csv')
SHELLS = ('bash', 'zsh', 'fish')
WELL_KNOWN_ALIASES = ('default', 'session')
GLOBAL_DESTS = frozenset({'help', 'format', 'color', 'pager'})
LIST_COLUMNS = ('label', 'collection', 'attributes', 'created', 'modified', 'content_type', 'path')
STATUS_COLUMNS = ('status', 'label', 'collection', 'attributes', 'path')
DESCRIBE_COLUMNS = ('collection', 'aliases', 'locked', 'secrets', 'created', 'modified', 'path')
ITEM_FIELDS = (('Collection', 'collection'), ('Created', 'created'), ('Modified', 'modified'),
               ('Content-Type', 'content_type'), ('Path', 'path'))
COLLECTION_FIELDS = (('Path', 'path'), ('Aliases', 'aliases'), ('Locked', 'locked'), ('Secrets', 'secrets'),
                     ('Created', 'created'), ('Modified', 'modified'))
STYLES = {'bold': '1', 'dim': '2', 'red': '31', 'green': '32', 'yellow': '33', 'cyan': '36'}


class CliError(Exception):
    """User-facing failure; reported on stderr with a non-zero exit code."""

    exit_code = EXIT_FAILURE


class UsageError(CliError):
    """Invalid command line; reported on stderr with exit code 2."""

    exit_code = EXIT_USAGE


class ExecError(CliError):
    """The command given to exec could not be started; uses the shell's 126/127 exit codes."""

    def __init__(self, message: str, exit_code: int):
        super().__init__(message)
        self.exit_code = exit_code


class Styler:
    """Wraps text in ANSI escapes when enabled."""

    def __init__(self, enabled: bool):
        self.enabled = enabled

    def __call__(self, text: str, *styles: str) -> str:
        if not self.enabled or not styles or not text:
            return text
        return f"\033[{';'.join(STYLES[name] for name in styles)}m{text}\033[0m"


def want_color(flag: bool | None, stream) -> bool:
    """Explicit --color/--no-color wins; otherwise color only on a terminal and when NO_COLOR is unset."""
    if flag is not None:
        return flag
    return stream.isatty() and 'NO_COLOR' not in os.environ


def scan_color_flag(argv: list[str]) -> bool | None:
    """Find --color/--no-color in raw argv (the last one wins) for use before argparse has finished."""
    flag = None
    for arg in argv:
        if arg == '--':
            break
        if arg in ('--color', '--no-color'):
            flag = arg == '--color'
    return flag


def pager_command() -> list[str] | None:
    command = shlex.split(os.environ.get('PAGER', '')) or ([shutil.which('less')] if shutil.which('less') else None)
    return command if command and shutil.which(command[0]) else None


def show_in_pager(text: str) -> None:
    """Pipe text through the pager; print directly when it fits on screen or no pager is available."""
    command = pager_command()
    if command is None or text.count('\n') < shutil.get_terminal_size().lines - 1:
        sys.stdout.write(text)
        return
    try:
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, text=True, env={'LESS': 'FRX', **os.environ})
    except OSError:
        sys.stdout.write(text)
        return
    try:
        proc.stdin.write(text)
        proc.stdin.close()
    except BrokenPipeError:
        pass
    while True:
        try:
            proc.wait()
            return
        except KeyboardInterrupt:
            continue


class Console:
    """Output settings (format, color, paging) plus helpers for writing to stdout/stderr."""

    def __init__(self, fmt: str = 'text', color: bool | None = None, pager: bool | None = None):
        self.fmt = fmt
        self.out = Styler(want_color(color, sys.stdout))
        self.err = Styler(want_color(color, sys.stderr))
        self.pager = sys.stdout.isatty() if pager is None else pager

    def info(self, message: str) -> None:
        print(message, file=sys.stderr)

    def error(self, message: str) -> None:
        print(f"{self.err('Error:', 'red', 'bold')} {message}", file=sys.stderr)

    def write(self, text: str, page: bool = False) -> None:
        if not text.endswith('\n'):
            text += '\n'
        if page and self.pager:
            show_in_pager(text)
        else:
            sys.stdout.write(text)


def parse_attributes(pairs: list[str] | None) -> dict[str, str]:
    """Parse KEY=VALUE strings into an attribute dict."""
    attributes: dict[str, str] = {}
    for pair in pairs or []:
        key, sep, value = pair.partition('=')
        if not sep or not key.strip():
            raise UsageError(f"Attribute '{pair}' must be in KEY=VALUE format.")
        attributes[key.strip()] = value.strip()
    return attributes


def resolve_collection(connection, name: str) -> Collection:
    """Return the collection named by label, alias or D-Bus path basename."""
    collection = next(
        (
            col
            for col in secretstorage.get_all_collections(connection)
            if name in (col.get_label(), col.collection_path.rsplit('/', 1)[-1])
        ),
        None,
    )
    if collection is None:
        try:
            collection = secretstorage.get_collection_by_alias(connection, name)
        except ItemNotFoundException:
            raise CliError(f"Collection '{name}' not found.") from None
    return collection


def select_collections(connection, args: argparse.Namespace) -> list[Collection]:
    """Collections chosen by -A/--all-collections, repeated -c/--collection, or else the default one."""
    if getattr(args, 'all_collections', False):
        return list(secretstorage.get_all_collections(connection))
    if getattr(args, 'collection', None):
        return [resolve_collection(connection, name) for name in args.collection]
    return [secretstorage.get_default_collection(connection)]


def _exit_on_signal(signum: int, _frame) -> None:
    """Turn termination signals into SystemExit so `finally` cleanup runs."""
    raise SystemExit(128 + signum)


@contextmanager
def open_connection() -> Iterator:
    """Connect to the Secret Service; the connection is always closed and signal handlers are restored."""
    try:
        connection = secretstorage.dbus_init()
    except SecretStorageException as err:
        raise CliError(f'Secret Service unavailable: {err}') from err
    previous_handlers = {sig: signal.signal(sig, _exit_on_signal) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        yield connection
    except SecretStorageException as err:
        raise CliError(f'Secret Service error: {err}') from err
    finally:
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)
        connection.close()


@contextmanager
def open_collections(args: argparse.Namespace, extra: str | None = None) -> Iterator[list[Collection]]:
    """
    Yield the selected collections, unlocked; with `extra`, that collection is resolved too and yielded last.

    Every collection that this process unlocked is locked again on every exit path (success, error, Ctrl-C,
    SIGTERM, SIGHUP); collections that were already unlocked are left alone.
    """
    with open_connection() as connection:
        collections = select_collections(connection, args)
        if extra is not None:
            collections.append(resolve_collection(connection, extra))
        unlocked_by_us: list[Collection] = []
        try:
            for collection in collections:
                if collection.is_locked():
                    print(f"Collection '{collection.get_label()}' is locked. Attempting to unlock...", file=sys.stderr)
                    unlocked_by_us.append(collection)
                    if collection.unlock() or collection.is_locked():
                        raise CliError(f"Collection '{collection.get_label()}' is still locked.")
            yield collections
        finally:
            for collection in reversed(unlocked_by_us):
                try:
                    if not collection.is_locked():
                        collection.lock()
                except SecretStorageException as err:
                    print(f'Warning: could not re-lock the collection: {err}', file=sys.stderr)


def name_matches(name: str, query: str | None, exact: bool) -> bool:
    if query is None:
        return True
    return name == query if exact else query.lower() in name.lower()


def matches(item: Item, query: str | None, exact: bool, attributes: dict[str, str]) -> bool:
    """True when the item satisfies every given label and attribute filter."""
    item_attrs = item.get_attributes()
    if any(item_attrs.get(key) != value for key, value in attributes.items()):
        return False
    if query is None:
        return True
    return name_matches(item.get_label() or '', query, exact)


def find_items(
        collections: list[Collection], query: str | None, exact: bool, attributes: dict[str, str]
) -> list[tuple[Collection, Item]]:
    return [
        (collection, item)
        for collection in collections
        for item in collection.get_all_items()
        if matches(item, query, exact, attributes)
    ]


def iso_time(timestamp: int) -> str | None:
    if not timestamp:
        return None
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def local_time(iso: str | None) -> str:
    if not iso:
        return '-'
    return datetime.fromisoformat(iso.replace('Z', '+00:00')).astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')


def item_record(collection: Collection, item: Item) -> dict:
    """Everything known about an item except its secret value."""
    return {
        'label': item.get_label() or '',
        'collection': collection.get_label(),
        'attributes': item.get_attributes(),
        'created': iso_time(item.get_created()),
        'modified': iso_time(item.get_modified()),
        'content_type': item.get_secret_content_type(),
        'path': item.item_path,
        'collection_path': collection.collection_path,
    }


def add_secret(record: dict, raw: bytes) -> dict:
    """Add a secret to a record; a non-UTF-8 secret is emitted as `secret_base64`."""
    try:
        return {**record, 'secret': raw.decode('utf-8')}
    except UnicodeDecodeError:
        return {**record, 'secret_base64': base64.b64encode(raw).decode('ascii')}


def csv_cell(value) -> str:
    if value is None:
        return ''
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (dict, list)):
        return json.dumps(value, sort_keys=True)
    return str(value)


def columns_of(records: list[dict], columns: tuple[str, ...] | None) -> tuple[str, ...]:
    return columns or tuple(dict.fromkeys(key for record in records for key in record))


def to_csv(records: list[dict], columns: tuple[str, ...] | None = None) -> str:
    columns = columns_of(records, columns)
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator='\n')
    writer.writerow(columns)
    for record in records:
        writer.writerow([csv_cell(record.get(column)) for column in columns])
    return buffer.getvalue()


def cell_text(value) -> str:
    """Plain, possibly multi-line text for one record value (table and md formats)."""
    if value is None:
        return ''
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, dict):
        return '\n'.join(f'{key}={entry}' for key, entry in sorted(value.items()))
    if isinstance(value, list):
        return ', '.join(str(entry) for entry in value)
    return str(value)


def heading(column: str) -> str:
    return column.replace('_', ' ')


def table_width() -> int:
    return shutil.get_terminal_size((120, 24)).columns


def box_characters() -> str:
    """Corner, tee, cross and line glyphs: unicode box drawing when stdout can encode it, else ASCII."""
    glyphs = '┌┬┐├┼┤└┴┘─│'
    try:
        glyphs.encode(sys.stdout.encoding or 'ascii')
    except UnicodeEncodeError:
        return '+++++++++-|'
    return glyphs


def fit_widths(natural: list[int], total: int, floor: int = 4, fixed: int = 20) -> list[int]:
    """
    Column widths adding up to `total`.

    The widest columns shrink first; short columns (up to `fixed`, e.g. timestamps) keep their width as long as the
    others can give way, and only then does everything shrink toward `floor`. Spare room is shared in proportion.
    """
    widths = list(natural)
    for lows in ([size if size <= fixed else 12 for size in natural], [floor] * len(natural)):
        while sum(widths) > total:
            shrinkable = [index for index, size in enumerate(widths) if size > lows[index]]
            if not shrinkable:
                break
            widths[max(shrinkable, key=widths.__getitem__)] -= 1
    spare = total - sum(widths)
    if spare > 0:
        weight = sum(natural) or 1
        widths = [width + spare * size // weight for width, size in zip(widths, natural)]
        widths[max(range(len(widths)), key=natural.__getitem__)] += total - sum(widths)
    return widths


def wrap_cell(lines: list[str], width: int) -> list[str]:
    return [part for line in lines for part in textwrap.wrap(line, width, break_on_hyphens=False) or ['']]


def render_table(records: list[dict], columns: tuple[str, ...], style: Styler, width: int) -> str:
    """Boxed table filling `width` columns; cells wrap onto extra lines when the terminal is too narrow."""
    if not records:
        return ''
    top_left, top, top_right, left, cross, right, bottom_left, bottom, bottom_right, dash, bar = box_characters()
    heads = [heading(column).upper() for column in columns]
    cells = [[cell_text(record.get(column)).split('\n') for column in columns] for record in records]
    natural = [max(len(head), *(len(line) for row in cells for line in row[index])) for index, head in enumerate(heads)]
    widths = fit_widths(natural, width - 3 * len(columns) - 1)
    rows = [[wrap_cell(lines, widths[index]) for index, lines in enumerate(row)] for row in cells]

    def rule(start: str, middle: str, end: str) -> str:
        return style(start + middle.join(dash * (size + 2) for size in widths) + end, 'dim')

    def render_row(parts: list[list[str]], *styles: str) -> list[str]:
        edge = style(bar, 'dim')
        return [
            edge + edge.join(f" {style((part[number] if number < len(part) else '').ljust(size), *styles)} "
                             for part, size in zip(parts, widths)) + edge
            for number in range(max(len(part) for part in parts))
        ]

    lines = [rule(top_left, top, top_right),
             *render_row([wrap_cell([head], size) for head, size in zip(heads, widths)], 'bold', 'cyan'),
             rule(left, cross, right)]
    spaced = any(len(part) > 1 for row in rows for part in row)
    for number, row in enumerate(rows):
        if spaced and number:
            lines.append(rule(left, cross, right))
        lines += render_row(row)
    lines.append(rule(bottom_left, bottom, bottom_right))
    return '\n'.join(lines)


MARKDOWN_SPECIAL = re.compile(r'([\\`*_<>\[\]|])')


def markdown_cell(value) -> str:
    return MARKDOWN_SPECIAL.sub(r'\\\1', cell_text(value)).replace('\n', '<br>')


def to_markdown(records: list[dict], columns: tuple[str, ...]) -> str:
    """GitHub-flavored markdown table."""
    if not records:
        return ''
    lines = ['| ' + ' | '.join(heading(column).title() for column in columns) + ' |',
             '| ' + ' | '.join('---' for _ in columns) + ' |']
    lines += ['| ' + ' | '.join(markdown_cell(record.get(column)) for column in columns) + ' |' for record in records]
    return '\n'.join(lines)


HCL_IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z0-9_-]*')
HCL_KEYWORDS = frozenset({'true', 'false', 'null'})
HCL_ESCAPES = {'b': r'\u0008', 'f': r'\u000c'}


def hcl_string(value) -> str:
    """Quoted HCL string: JSON escaping (minus \\b and \\f, which HCL lacks) plus escaped template sequences."""
    text = json.dumps(str(value), ensure_ascii=False)
    text = re.sub(r'\\(u[0-9a-fA-F]{4}|.)', lambda m: HCL_ESCAPES.get(m.group(1), m.group(0)), text)
    return text.replace('${', '$${').replace('%{', '%%{')


def hcl_key(key: str) -> str:
    return key if HCL_IDENTIFIER.fullmatch(key) and key not in HCL_KEYWORDS else hcl_string(key)


def hcl_value(value, indent: int) -> str:
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, dict):
        if not value:
            return '{}'
        width = max(len(hcl_key(key)) for key in value)
        pad = ' ' * (indent + 2)
        body = [f'{pad}{hcl_key(key):<{width}} = {hcl_value(entry, indent + 2)}'
                for key, entry in sorted(value.items())]
        return '{\n' + '\n'.join(body) + '\n' + ' ' * indent + '}'
    if isinstance(value, list):
        return '[' + ', '.join(hcl_value(entry, indent) for entry in value) + ']'
    return hcl_string(value)


def to_hcl(records: list[dict], kind: str, label_key: str) -> str:
    """HCL2 document with one `kind "label" { ... }` block per record; null values are left out."""
    blocks = []
    for record in records:
        fields = {key: hcl_value(value, 2) for key, value in record.items() if key != label_key and value is not None}
        single = {key: value for key, value in fields.items() if '\n' not in value}
        width = max((len(key) for key in single), default=0)
        body = [f'  {key:<{width}} = {value}' for key, value in single.items()]
        body += [f'  {key} = {value}' for key, value in fields.items() if key not in single]
        blocks.append('\n'.join([f'{kind} {hcl_string(record[label_key])} {{', *body, '}']))
    return '\n\n'.join(blocks)


def field_text(key: str, value) -> str:
    if key in ('created', 'modified'):
        return local_time(value)
    if isinstance(value, bool):
        return 'yes' if value else 'no'
    return cell_text(value) or '-'


def render_records(records: list[dict], style: Styler, title_key: str, fields: tuple[tuple[str, str], ...],
                   noun: str, untitled: str = '(no label)') -> str:
    """Pretty, terminal-oriented view: a title line, then one `Name  value` row per field of each record."""
    blocks = []
    for record in records:
        lines = [style(record[title_key] or untitled, 'bold', 'green')]
        lines += [f"    {style(f'{name:<13}', 'cyan')}{field_text(key, record.get(key))}" for name, key in fields]
        if record.get('attributes'):
            width = max(len(key) for key in record['attributes'])
            lines.append(f"    {style('Attributes', 'cyan')}")
            lines += [f'        {style(f"{key:<{width}}", "yellow")}  {value}' for key, value in sorted(
                record['attributes'].items())]
        blocks.append('\n'.join(lines))
    footer = style(f'{len(records)} {noun}(s)', 'dim')
    return '\n\n'.join(blocks) + f'\n\n{footer}'


def emit(console: Console, records: list[dict], default_text: str, columns: tuple[str, ...] | None = None,
         page: bool = False, kind: str = 'secret', label_key: str = 'label') -> None:
    """Write records in the selected --format; `default_text` is what the caller wants for the text format."""
    fmt = console.fmt
    if fmt == 'json':
        text = json.dumps(records, indent=2)
    elif fmt == 'csv':
        text = to_csv(records, columns)
    elif fmt == 'table':
        text = render_table(records, columns_of(records, columns), console.out, table_width())
    elif fmt == 'md':
        text = to_markdown(records, columns_of(records, columns))
    elif fmt == 'hcl':
        text = to_hcl(records, kind, label_key)
    else:
        text = default_text
    if text:
        console.write(text, page)


def read_secret(label: str) -> bytes:
    """Read a secret from piped stdin, or prompt twice without echo on a terminal. Never from arguments."""
    if not sys.stdin.isatty():
        value = sys.stdin.buffer.read()
    else:
        try:
            first = getpass.getpass(prompt=f"Enter secret for '{label}': ")
            if getpass.getpass(prompt='Confirm secret: ') != first:
                raise CliError('Secrets do not match.')
        except (KeyboardInterrupt, EOFError) as err:
            raise CliError('Operation cancelled.') from err
        value = first.encode('utf-8')
    if not value:
        raise CliError('Secret payload cannot be empty.')
    return value


def action_list(args: argparse.Namespace, console: Console) -> int:
    attributes = parse_attributes(args.attribute)
    if args.label is not None and args.query is not None:
        raise UsageError('list takes either QUERY or -l/--label, not both.')
    query, exact = (args.label, True) if args.label is not None else (args.query, args.exact)
    with open_collections(args) as collections:
        records = [item_record(col, item) for col, item in find_items(collections, query, exact, attributes)]
    default_text = render_records(records, console.out, 'label', ITEM_FIELDS, 'secret') if records else ''
    emit(console, records, default_text, LIST_COLUMNS, page=True)
    if records:
        return EXIT_OK
    console.info('No matching secrets found.')
    return EXIT_OK if query is None and not attributes else EXIT_FAILURE


def collection_time(collection: Collection, name: str) -> str | None:
    """Created/Modified timestamp of a collection; secretstorage has no accessor, so read the D-Bus property."""
    try:
        return iso_time(collection._collection.get_property(name))
    except Exception:  # private API and D-Bus errors alike: the timestamp is informational only
        return None


def collection_record(connection, collection: Collection) -> dict:
    """Everything known about a collection without unlocking it (and never any secret)."""
    path = collection.collection_path
    aliases = []
    for alias in WELL_KNOWN_ALIASES:
        try:
            if secretstorage.get_collection_by_alias(connection, alias).collection_path == path:
                aliases.append(alias)
        except SecretStorageException:
            pass
    try:
        count = len(list(collection.get_all_items()))
    except SecretStorageException:
        count = None
    return {
        'collection': collection.get_label(),
        'aliases': aliases,
        'locked': collection.is_locked(),
        'secrets': count,
        'created': collection_time(collection, 'Created'),
        'modified': collection_time(collection, 'Modified'),
        'path': path,
    }


def action_describe(args: argparse.Namespace, console: Console) -> int:
    with open_connection() as connection:
        records = [
            record
            for record in (collection_record(connection, col) for col in secretstorage.get_all_collections(connection))
            if any(name_matches(name, args.query, args.exact)
                   for name in (record['collection'], record['path'].rsplit('/', 1)[-1], *record['aliases']))
        ]
    default_text = ''
    if records:
        default_text = render_records(records, console.out, 'collection', COLLECTION_FIELDS, 'collection')
    emit(console, records, default_text, DESCRIBE_COLUMNS, page=True, kind='collection', label_key='collection')
    if records:
        return EXIT_OK
    console.info('No matching collections found.')
    return EXIT_OK if args.query is None else EXIT_FAILURE


def action_get(args: argparse.Namespace, console: Console) -> int:
    attributes = parse_attributes(args.attribute)
    if not attributes and args.label is None:
        raise UsageError('get needs at least one -a/--attribute or -l/--label filter.')
    with open_collections(args) as collections:
        found = find_items(collections, args.label, True, attributes)
        if not found:
            console.info('No matching secret found.')
            return EXIT_FAILURE
        if len(found) > 1:
            console.info(f'{len(found)} secrets match; using the first. Narrow the filters to be certain.')
        collection, item = found[0]
        record, secret = item_record(collection, item), item.get_secret()
    if console.fmt == 'text':
        sys.stdout.buffer.write(secret)
        if sys.stdout.isatty():
            sys.stdout.buffer.write(b'\n')
        sys.stdout.buffer.flush()
    else:
        emit(console, [add_secret(record, secret)], '')
    return EXIT_OK


def action_set(args: argparse.Namespace, console: Console) -> int:
    if not args.label:
        raise UsageError('set needs -l/--label LABEL.')
    if len(args.collection or []) > 1:
        raise UsageError('set stores into exactly one collection.')
    attributes = parse_attributes(args.attribute)
    secret = read_secret(args.label)
    with open_collections(args) as collections:
        collection = collections[0]
        item = collection.create_item(args.label, attributes, secret, replace=True)
        record = {'status': 'stored', **item_record(collection, item)}
    emit(console, [record], f"Stored {record['label']!r} in collection {record['collection']!r}.", STATUS_COLUMNS)
    return EXIT_OK


def action_delete(args: argparse.Namespace, console: Console) -> int:
    attributes = parse_attributes(args.attribute)
    if not attributes and args.label is None:
        raise UsageError('delete needs at least one -a/--attribute or -l/--label filter.')
    with open_collections(args) as collections:
        found = find_items(collections, args.label, True, attributes)
        if not found:
            console.info('No matching secret found.')
            return EXIT_FAILURE
        verb = 'Would delete' if args.dry_run else 'Matched'
        for collection, item in found:
            console.info(f"{verb}: {item.get_label()!r} in {collection.get_label()!r} {item.get_attributes()}")
        status = 'would-delete' if args.dry_run else 'deleted'
        records = [{'status': status, **item_record(collection, item)} for collection, item in found]
        if not args.dry_run:
            confirm(f'Delete {len(found)} secret(s)?', args.yes, 'delete')
            for _, item in found:
                item.delete()
    emit(console, records, f"{'Would delete' if args.dry_run else 'Deleted'} {len(records)} secret(s).", STATUS_COLUMNS)
    return EXIT_OK


def action_move(args: argparse.Namespace, console: Console) -> int:
    if not args.to:
        raise UsageError('move needs -t/--to COLLECTION.')
    attributes = parse_attributes(args.attribute)
    if not attributes and args.label is None:
        raise UsageError('move needs at least one -a/--attribute or -l/--label filter.')
    with open_collections(args, extra=args.to) as collections:
        *sources, target = collections
        found = [(col, item) for col, item in find_items(sources, args.label, True, attributes)
                 if col.collection_path != target.collection_path]
        if not found:
            console.info('No matching secret found outside the destination collection.')
            return EXIT_FAILURE
        existing = [item.get_attributes() for item in target.get_all_items()]
        clashes = [item for _, item in found if item.get_attributes() in existing]
        if clashes and not args.replace:
            names = ', '.join(repr(item.get_label()) for item in clashes)
            raise CliError(f'Destination {target.get_label()!r} already has a secret with the same attributes as: '
                           f'{names}. Use --replace to overwrite.')
        verb = 'Would move' if args.dry_run else 'Matched'
        for collection, item in found:
            renamed = f' as {args.new_label!r}' if args.new_label else ''
            console.info(f"{verb}: {item.get_label()!r}{renamed} {item.get_attributes()} "
                         f"{collection.get_label()!r} -> {target.get_label()!r}")
        records = []
        if not args.dry_run:
            confirm(f'Move {len(found)} secret(s) to {target.get_label()!r}?', args.yes, 'move')
        for collection, item in found:
            old = item_record(collection, item)
            if not args.dry_run:
                secret = item.get_secret()
                new = target.create_item(args.new_label or item.get_label() or '', item.get_attributes(), secret,
                                         replace=args.replace, content_type=item.get_secret_content_type())
                if new.get_secret() != secret:
                    new.delete()
                    raise CliError(f"Copy of {old['label']!r} did not verify; the original was kept.")
                item.delete()
                old = item_record(target, new)
            records.append({'status': 'would-move' if args.dry_run else 'moved', **old})
    emit(console, records, f"{'Would move' if args.dry_run else 'Moved'} {len(records)} secret(s) "
                           f"to {records[0]['collection'] if not args.dry_run else args.to!r}.", STATUS_COLUMNS)
    return EXIT_OK


def confirm(question: str, assume_yes: bool, action: str) -> None:
    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise CliError(f'Refusing to {action} non-interactively without -y/--yes.')
    print(f'{question} [y/N] ', end='', file=sys.stderr, flush=True)
    try:
        answer = input().strip().lower()
    except EOFError:
        answer = ''
    if answer not in ('y', 'yes'):
        raise CliError('Operation cancelled.')


def action_update(args: argparse.Namespace, console: Console) -> int:
    attributes = parse_attributes(args.attribute)
    if not attributes and args.label is None:
        raise UsageError('update needs at least one -a/--attribute or -l/--label filter.')
    additions = parse_attributes(args.add_attribute)
    removals = args.remove_attribute or []
    if args.new_label is None and not additions and not removals and not args.value:
        raise UsageError('update needs at least one of --new-label, --add-attribute, --remove-attribute or --value.')
    if set(additions) & set(removals):
        raise UsageError('The same attribute cannot be both added and removed.')
    secret = read_secret(args.new_label or args.label or 'the matched secrets') if args.value else None
    with open_collections(args) as collections:
        found = find_items(collections, args.label, True, attributes)
        if not found:
            console.info('No matching secret found.')
            return EXIT_FAILURE
        for collection, item in found:
            verb = 'Would update' if args.dry_run else 'Matched'
            console.info(f"{verb}: {item.get_label()!r} in {collection.get_label()!r} {item.get_attributes()}")
        if not args.dry_run:
            confirm(f'Update {len(found)} secret(s)?', args.yes, 'update')
            for _, item in found:
                if args.new_label is not None:
                    item.set_label(args.new_label)
                if additions or removals:
                    kept = {key: value for key, value in item.get_attributes().items() if key not in removals}
                    item.set_attributes({**kept, **additions})
                if secret is not None:
                    item.set_secret(secret)
        status = 'would-update' if args.dry_run else 'updated'
        records = [{'status': status, **item_record(collection, item)} for collection, item in found]
    emit(console, records, f"{'Would update' if args.dry_run else 'Updated'} {len(records)} secret(s).", STATUS_COLUMNS)
    return EXIT_OK


def env_variable(item: Item, args: argparse.Namespace) -> str:
    """Environment variable name for one secret in --all-matches mode: PREFIX + sanitized label or attribute."""
    label = item.get_label() or ''
    source = item.get_attributes().get(args.name_attribute) if args.name_attribute else label
    if source is None:
        raise CliError(f"Secret {label!r} has no attribute '{args.name_attribute}' to name its variable.")
    name = args.prefix + re.sub(r'[^A-Za-z0-9]+', '_', source).strip('_').upper()
    if not ENV_NAME.fullmatch(name):
        raise CliError(f'Cannot derive a valid environment variable name for secret {label!r}.')
    return name


def action_exec(args: argparse.Namespace, console: Console) -> int:
    if not args.argv:
        raise UsageError("exec needs a COMMAND after '--'.")
    attributes = parse_attributes(args.attribute)
    if not args.all_matches and not attributes and args.label is None:
        raise UsageError('exec needs -l/--label or -a/--attribute to choose a secret, or --all-matches.')
    if not ENV_NAME.fullmatch(args.var):
        raise UsageError(f"'{args.var}' is not a valid environment variable name.")
    injected: dict[str, str] = {}
    records = []
    with open_collections(args) as collections:
        found = find_items(collections, args.label, True, attributes)
        if not found:
            console.info('No matching secret found.')
            return EXIT_FAILURE
        if not args.all_matches:
            if len(found) > 1:
                console.info(f'{len(found)} secrets match; using the first. Narrow the filters to be certain.')
            found = found[:1]
        for collection, item in found:
            name = env_variable(item, args) if args.all_matches else args.var
            if name in injected:
                raise CliError(f"Two secrets map to the environment variable '{name}'.")
            try:
                value = item.get_secret().decode('utf-8')
            except UnicodeDecodeError:
                raise CliError(f'Secret {item.get_label()!r} is not valid UTF-8 and cannot be injected.') from None
            if '\0' in value:
                raise CliError(f'Secret {item.get_label()!r} contains a NUL byte and cannot be injected.')
            injected[name] = value
            records.append({'variable': name, 'label': item.get_label() or '', 'collection': collection.get_label()})
    if args.dry_run:
        lines = [f"{record['variable']} <- {record['label']!r} ({record['collection']})" for record in records]
        emit(console, records, '\n'.join(lines), kind='variable', label_key='variable')
        return EXIT_OK
    sys.stdout.flush()
    sys.stderr.flush()
    try:
        os.execvpe(args.argv[0], args.argv, {**os.environ, **injected})
    except FileNotFoundError:
        raise ExecError(f'Command not found: {args.argv[0]}', 127) from None
    except OSError as err:
        raise ExecError(f'Cannot execute {args.argv[0]}: {err.strerror}', 126) from err


def action_create(args: argparse.Namespace, console: Console) -> int:
    name = args.collection
    if not name:
        raise UsageError('create needs -c/--collection COLLECTION.')
    with open_connection() as connection:
        if any(col.get_label() == name for col in secretstorage.get_all_collections(connection)):
            raise CliError(f"Collection '{name}' already exists.")
        if args.alias:
            try:
                secretstorage.get_collection_by_alias(connection, args.alias)
            except ItemNotFoundException:
                pass
            else:
                raise CliError(f"Alias '{args.alias}' is already in use.")
        collection = secretstorage.create_collection(connection, name, args.alias or '')
        record = {
            'status': 'created',
            'collection': collection.get_label(),
            'path': collection.collection_path,
            'alias': args.alias,
            'locked': collection.is_locked(),
        }
    emit(console, [record], f"Created collection {record['collection']!r}.", kind='collection',
         label_key='collection')
    return EXIT_OK


def action_destroy(args: argparse.Namespace, console: Console) -> int:
    if not args.collection:
        raise UsageError('destroy needs at least one -c/--collection COLLECTION.')
    with open_connection() as connection:
        targets = {col.collection_path: col
                   for col in (resolve_collection(connection, name) for name in args.collection)}
        records = []
        for collection in targets.values():
            try:
                count = len(list(collection.get_all_items()))
            except SecretStorageException:
                count = None
            size = 'unknown number of' if count is None else count
            verb = 'Would destroy' if args.dry_run else 'Matched'
            console.info(f'{verb}: collection {collection.get_label()!r} ({size} secret(s))')
            records.append({'status': 'would-destroy' if args.dry_run else 'destroyed',
                            'collection': collection.get_label(), 'path': collection.collection_path,
                            'secrets': count})
        if not args.dry_run:
            confirm(f'Permanently destroy {len(targets)} collection(s) and every secret in them?', args.yes, 'destroy')
            for collection in targets.values():
                collection.delete()
    emit(console, records, f"{'Would destroy' if args.dry_run else 'Destroyed'} {len(records)} collection(s).",
         kind='collection', label_key='collection')
    return EXIT_OK


def set_lock_state(args: argparse.Namespace, console: Console, lock: bool) -> int:
    """Persistently lock or unlock the selected collections (no automatic restore)."""
    verb = 'lock' if lock else 'unlock'
    records, lines = [], []
    with open_connection() as connection:
        for collection in select_collections(connection, args):
            label = collection.get_label()
            changed = collection.is_locked() != lock
            if changed:
                if lock:
                    collection.lock()
                else:
                    collection.unlock()
                if collection.is_locked() != lock:
                    raise CliError(f"Could not {verb} collection '{label}'.")
            records.append(
                {'collection': label, 'path': collection.collection_path, 'locked': lock, 'changed': changed}
            )
            lines.append(f"{verb.capitalize()}ed collection '{label}'." if changed
                         else f"Collection '{label}' is already {verb}ed.")
    emit(console, records, '\n'.join(lines), kind='collection', label_key='collection')
    return EXIT_OK


def action_lock(args: argparse.Namespace, console: Console) -> int:
    return set_lock_state(args, console, lock=True)


def action_unlock(args: argparse.Namespace, console: Console) -> int:
    return set_lock_state(args, console, lock=False)


def action_help(args: argparse.Namespace, console: Console) -> int:
    """Render top-level or per-action help for `help [ACTION]` and for any -h/--help."""
    topic = args.action_name
    if topic == 'help' and not args.help:
        topic = args.topic
    if topic is None:
        console.write(render_top_help(args.parser, args.parsers, console.out), page=True)
        return EXIT_OK
    action = ACTION_BY_NAME.get(topic)
    if action is None:
        raise UsageError(f"Unknown action '{topic}'.")
    console.write(render_action_help(action, args.parsers[action.name], console.out), page=True)
    return EXIT_OK


def completion_flags(parser: argparse.ArgumentParser, global_ones: bool) -> list[dict]:
    return [
        {
            'names': tuple(act.option_strings),
            'metavar': (act.metavar or act.dest.upper()) if act.nargs != 0 else None,
            'help': act.help or '',
            'choices': tuple(act.choices or ()),
            'repeat': isinstance(act, argparse._AppendAction),
        }
        for act in parser._actions
        if act.option_strings and (act.dest in GLOBAL_DESTS) == global_ones
    ]


def completion_model(top: argparse.ArgumentParser, parsers: dict[str, argparse.ArgumentParser]) -> dict:
    """What the completion scripts need, read from the parsers the real command line uses."""
    actions = []
    for action in ACTIONS:
        parser = parsers[action.name]
        positional = next((act for act in parser._actions if not act.option_strings), None)
        values = tuple(ACTION_BY_NAME) if action.name == 'help' else tuple(getattr(positional, 'choices', None) or ())
        actions.append({'words': (action.name, *action.aliases), 'summary': action.summary,
                        'flags': completion_flags(parser, False), 'values': values})
    flags = completion_flags(top, True) + [flag for action in actions for flag in action['flags']]
    return {
        'global': completion_flags(top, True),
        'actions': actions,
        'words': [word for action in actions for word in action['words']],
        'value_flags': sorted({name for flag in flags if flag['metavar'] for name in flag['names']}),
        'choice_flags': [flag for flag in flags if flag['choices']],
    }


def flag_words(flags: list[dict]) -> str:
    return ' '.join(name for flag in flags for name in flag['names'])


def shell_function_name() -> str:
    return '_' + re.sub(r'\W', '_', PROG)


def fill(template: str, **values: str) -> str:
    for key, value in values.items():
        template = template.replace(f'@{key}@', value)
    return template


BASH_TEMPLATE = r'''# bash completion for @PROG@; load it with: eval "$(@PROG@ completion bash)"
@FN@() {
    local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}
    local action='' dashes=0 i word words=''
    for ((i = 1; i < COMP_CWORD; i++)); do
        word=${COMP_WORDS[i]}
        case $word in
            --) dashes=$i; break ;;
            @VALUE_FLAGS@) ((i++)) ;;
            -*) ;;
            @ACTION_WORDS@) if [[ -z $action ]]; then action=$word; fi ;;
        esac
    done
    if ((dashes)); then
        if ((COMP_CWORD == dashes + 1)); then
            COMPREPLY=($(compgen -c -- "$cur"))
        else
            COMPREPLY=($(compgen -f -- "$cur"))
        fi
        return
    fi
    case $prev in
@CHOICES@
        @VALUE_FLAGS@) return ;;
    esac
    if [[ $cur == -* ]]; then
        case $action in
@FLAG_CASES@
            *) words='@GLOBAL_FLAGS@' ;;
        esac
    else
        case $action in
@VALUE_CASES@
            '') words='@ACTION_WORDS_LIST@' ;;
        esac
    fi
    COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
complete -F @FN@ @PROG@
'''


def bash_completion(model: dict) -> str:
    global_flags = flag_words(model['global'])
    choices = []
    for flag in model['choice_flags']:
        values = ' '.join(flag['choices'])
        names = '|'.join(flag['names'])
        choices.append(f"        {names}) COMPREPLY=($(compgen -W '{values}' -- \"$cur\")); return ;;")
    flag_cases = [f"            {'|'.join(action['words'])}) words='{flag_words(action['flags'])} {global_flags}' ;;"
                  for action in model['actions']]
    value_cases = [f"            {'|'.join(action['words'])}) words='{' '.join(action['values'])}' ;;"
                   for action in model['actions'] if action['values']]
    return fill(
        BASH_TEMPLATE, PROG=PROG, FN=shell_function_name(), VALUE_FLAGS='|'.join(model['value_flags']),
        ACTION_WORDS='|'.join(model['words']), ACTION_WORDS_LIST=' '.join(model['words']),
        CHOICES='\n'.join(choices), FLAG_CASES='\n'.join(flag_cases), VALUE_CASES='\n'.join(value_cases),
        GLOBAL_FLAGS=global_flags,
    )


def zsh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\\''") + "'"


def zsh_specs(flags: list[dict]) -> str:
    """_arguments option specs, one per flag name."""
    specs = []
    for flag in flags:
        explanation = flag['help'].replace('[', '(').replace(']', ')').replace(':', ' -')
        exclusion = '*' if flag['repeat'] else f"({' '.join(flag['names'])})"
        choices = f"({' '.join(flag['choices'])})" if flag['choices'] else ''
        value = f"[{explanation}]:{flag['metavar']}:{choices}" if flag['metavar'] else f'[{explanation}]'
        specs += [zsh_quote(f'{exclusion}{name}{value}') for name in flag['names']]
    return ' '.join(specs)


ZSH_TEMPLATE = r'''#compdef @PROG@
# zsh completion for @PROG@: save it as _@PROG@ in a directory on $fpath (then run compinit),
# or load it with: source <(@PROG@ completion zsh)

@FN@() {
    local action='' word skip=0 dashes=0 index=0 i
    for ((i = 2; i < CURRENT; i++)); do
        word=$words[i]
        if ((skip)); then
            skip=0
            continue
        fi
        case $word in
            --) dashes=$i; break ;;
            @VALUE_FLAGS@) skip=1 ;;
            -*) ;;
            @ACTION_WORDS@) if [[ -z $action ]]; then action=$word; index=$i; fi ;;
        esac
    done
    if ((dashes)); then
        words=("${(@)words[dashes+1,-1]}")
        ((CURRENT -= dashes))
        _normal
        return
    fi
    local -a actions
    actions=(@DESCRIBED@)
    if [[ -z $action ]]; then
        if [[ $PREFIX == -* || $words[CURRENT-1] == (@VALUE_FLAGS@) ]]; then
            _arguments @GLOBAL_SPECS@
        else
            _describe -t actions 'action' actions
        fi
        return
    fi
    words[index]=()
    ((CURRENT--))
    case $action in
@CASES@
    esac
}

if [[ $funcstack[1] == @FN@ ]]; then
    @FN@ "$@"
else
    compdef @FN@ @PROG@
fi
'''


def zsh_completion(model: dict) -> str:
    global_specs = zsh_specs(model['global'])
    described = ' '.join(zsh_quote(f"{word}:{action['summary'].replace(':', ' -')}")
                         for action in model['actions'] for word in action['words'])
    cases = []
    for action in model['actions']:
        specs = f"{zsh_specs(action['flags'])} {global_specs}"
        if action['values']:
            specs += ' ' + zsh_quote(f"1:{action['words'][0]}:({' '.join(action['values'])})")
        cases.append(f"        {'|'.join(action['words'])}) _arguments {specs} ;;")
    return fill(
        ZSH_TEMPLATE, PROG=PROG, FN=shell_function_name(), VALUE_FLAGS='|'.join(model['value_flags']),
        ACTION_WORDS='|'.join(model['words']), DESCRIBED=described, GLOBAL_SPECS=global_specs, CASES='\n'.join(cases),
    )


def fish_quote(text: str) -> str:
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def fish_options(flag: dict) -> str:
    parts = [f'-s {name[1:]}' if not name.startswith('--') else f'-l {name[2:]}' for name in flag['names']]
    if flag['metavar']:
        parts.append('-x' if flag['choices'] else '-r')
    if flag['choices']:
        parts.append(f"-a {fish_quote(' '.join(flag['choices']))}")
    parts.append(f"-d {fish_quote(flag['help'])}")
    return ' '.join(parts)


FISH_TEMPLATE = r'''# fish completion for @PROG@: save it as ~/.config/fish/completions/@PROG@.fish,
# or load it with: @PROG@ completion fish | source

function @FN@_action
    set -l skip 0
    set -l words (commandline -opc)
    set -e words[1]
    for word in $words
        if test $skip -eq 1
            set skip 0
            continue
        end
        switch $word
            case --
                return 1
            case @VALUE_FLAGS@
                set skip 1
            case '-*'
            case @ACTION_WORDS@
                echo $word
                return 0
        end
    end
    return 1
end

function @FN@_none
    not @FN@_action >/dev/null
end

function @FN@_is
    set -l action (@FN@_action); or return 1
    contains -- $action $argv
end

function @FN@_dashes
    contains -- -- (commandline -opc)
end

complete -c @PROG@ -f
complete -c @PROG@ -n '@FN@_dashes' -F
complete -c @PROG@ -n '@FN@_dashes' -a '(__fish_complete_command)'
'''


def fish_completion(model: dict) -> str:
    fn = shell_function_name()
    lines = [f"complete -c {PROG} -n 'not {fn}_dashes' {fish_options(flag)}" for flag in model['global']]
    for action in model['actions']:
        for word in action['words']:
            lines.append(f"complete -c {PROG} -n '{fn}_none' -a {word} -d {fish_quote(action['summary'])}")
        condition = f"'{fn}_is {' '.join(action['words'])}'"
        lines += [f'complete -c {PROG} -n {condition} {fish_options(flag)}' for flag in action['flags']]
        if action['values']:
            lines.append(f"complete -c {PROG} -n {condition} -a {fish_quote(' '.join(action['values']))}")
    template = fill(FISH_TEMPLATE, PROG=PROG, FN=fn, VALUE_FLAGS=' '.join(model['value_flags']),
                    ACTION_WORDS=' '.join(model['words']))
    return template + '\n'.join(lines) + '\n'


def action_completion(args: argparse.Namespace, console: Console) -> int:
    shell = args.shell or os.path.basename(os.environ.get('SHELL', ''))
    if shell not in SHELLS:
        raise UsageError(f"Cannot tell which shell to complete for; name one of: {', '.join(SHELLS)}.")
    model = completion_model(args.parser, args.parsers)
    generators = {'bash': bash_completion, 'zsh': zsh_completion, 'fish': fish_completion}
    sys.stdout.write(generators[shell](model))
    return EXIT_OK


@dataclass(frozen=True)
class Action:
    """One CLI action: parser wiring plus the metadata the help renderer needs."""

    name: str
    group: str
    summary: str
    usage: str
    handler: Callable[[argparse.Namespace, Console], int]
    configure: Callable[[argparse.ArgumentParser], None]
    description: str = ''
    aliases: tuple[str, ...] = ()
    notes: tuple[str, ...] = ()
    examples: tuple[tuple[str, str], ...] = ()
    synopsis: tuple[str, ...] = ()


def add_attribute_option(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('-a', '--attribute', action='append', metavar='KEY=VALUE',
                        help='Match secrets having this attribute; repeatable.')


def add_label_option(parser: argparse.ArgumentParser, text: str = 'Match secrets with exactly this label.') -> None:
    parser.add_argument('-l', '--label', metavar='LABEL', help=text)


def add_collection_options(parser: argparse.ArgumentParser, verb: str, several: bool = True) -> None:
    parser.add_argument('-c', '--collection', action='append', metavar='COLLECTION',
                        help=f'Collection to {verb}, by label, alias or path name'
                             f'{"; repeatable" if several else ""}. Default: the default collection.')
    if several:
        parser.add_argument('-A', '--all-collections', action='store_true', help='Use every collection.')


def add_query_argument(parser: argparse.ArgumentParser, what: str, whole: str) -> None:
    parser.add_argument('query', nargs='?', metavar='QUERY', help=f'Case-insensitive substring of the {what} to match.')
    parser.add_argument('-e', '--exact', action='store_true', help=f'Match QUERY against the whole {whole}.')


def configure_list(parser: argparse.ArgumentParser) -> None:
    add_query_argument(parser, 'secret label', 'label')
    add_label_option(parser)
    add_attribute_option(parser)
    add_collection_options(parser, 'search')


def configure_describe(parser: argparse.ArgumentParser) -> None:
    add_query_argument(parser, 'collection label, alias or path name', 'name')


def configure_get(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser)
    add_attribute_option(parser)
    add_collection_options(parser, 'search')


def configure_set(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser, 'Label of the secret to store (required).')
    parser.add_argument('-a', '--attribute', action='append', metavar='KEY=VALUE',
                        help='Identity attribute stored with the secret; repeatable.')
    add_collection_options(parser, 'store into', several=False)


def configure_delete(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser)
    add_attribute_option(parser)
    parser.add_argument('-n', '--dry-run', action='store_true', help='Show what would be deleted and exit.')
    parser.add_argument('-y', '--yes', action='store_true', help='Delete without asking for confirmation.')
    add_collection_options(parser, 'delete from')


def configure_move(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser)
    add_attribute_option(parser)
    add_collection_options(parser, 'move from')
    parser.add_argument('-t', '--to', metavar='COLLECTION',
                        help='Destination collection, by label, alias or path name (required).')
    parser.add_argument('--new-label', metavar='LABEL', help='Give the moved secrets this label.')
    parser.add_argument('--replace', action='store_true',
                        help='Overwrite a destination secret that has the same attributes.')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Show what would be moved and exit.')
    parser.add_argument('-y', '--yes', action='store_true', help='Move without asking for confirmation.')


def configure_update(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser)
    add_attribute_option(parser)
    parser.add_argument('--new-label', metavar='LABEL', help='Replace the label of the matched secrets.')
    parser.add_argument('--add-attribute', action='append', metavar='KEY=VALUE',
                        help='Add or overwrite an attribute; repeatable.')
    parser.add_argument('--remove-attribute', action='append', metavar='KEY', help='Remove an attribute; repeatable.')
    parser.add_argument('--value', action='store_true',
                        help='Replace the secret value, read from piped stdin or prompted for twice without echo.')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Show what would be updated and exit.')
    parser.add_argument('-y', '--yes', action='store_true', help='Update without asking for confirmation.')
    add_collection_options(parser, 'update in')


def configure_exec(parser: argparse.ArgumentParser) -> None:
    add_label_option(parser)
    add_attribute_option(parser)
    parser.add_argument('-v', '--var', metavar='VARIABLE', default='SECRET',
                        help='Environment variable receiving the secret (default: SECRET).')
    parser.add_argument('-m', '--all-matches', action='store_true',
                        help='Inject every matching secret, each named after its label (or --name-attribute).')
    parser.add_argument('-p', '--prefix', metavar='PREFIX', default='',
                        help='Prefix for the variable names generated by --all-matches.')
    parser.add_argument('--name-attribute', metavar='KEY',
                        help='Name --all-matches variables after this attribute instead of the label.')
    parser.add_argument('-n', '--dry-run', action='store_true',
                        help='Show which variables would be set (never their values) and exit.')
    add_collection_options(parser, 'search')
    parser.add_argument('argv', nargs='*', metavar='COMMAND',
                        help="Program to run, followed by its own arguments (ARG...), after a '--'.")


def configure_create(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('-c', '--collection', metavar='COLLECTION', help='Label of the new collection (required).')
    parser.add_argument('--alias', metavar='ALIAS', help='Alias for the collection (e.g. "default").')


def configure_destroy(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('-c', '--collection', action='append', metavar='COLLECTION',
                        help='Collection to destroy, by label, alias or path name; repeatable (required).')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Show what would be destroyed and exit.')
    parser.add_argument('-y', '--yes', action='store_true', help='Destroy without asking for confirmation.')


def configure_lock(parser: argparse.ArgumentParser) -> None:
    add_collection_options(parser, 'act on')


def configure_help(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('topic', nargs='?', metavar='ACTION', help='Action (or alias) to show help for.')


def configure_completion(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('shell', nargs='?', choices=SHELLS, metavar='SHELL',
                        help='Shell to generate completions for (default: the one named by $SHELL).')


GROUPS = ('Use secrets', 'Modify secrets', 'Manage collections', 'Help')
ACTIONS = (
    Action(
        'list', 'Use secrets', 'List secrets matching filters in one or more collections.',
        'list [QUERY]', action_list, configure_list,
        synopsis=('[-e] [-l LABEL] [-a KEY=VALUE]... [-c COLLECTION... | -A] [QUERY]',),
        description='Show every secret (or those matching QUERY and -a filters) with all metadata except the secret '
                    'value, which list never prints; use get for that.',
        aliases=('ls', 'search'),
        notes=('Exits 1 when a QUERY or -a filter matches nothing.',),
        examples=(
            ('List every secret in the default collection', f'{PROG} list'),
            ('Labels containing "token" in all collections, as a table', f'{PROG} list token -A --format table'),
            ('Filter by attribute and process the JSON',
             f"{PROG} list -a service=github --format json | jq '.[].label'"),
        ),
    ),
    Action(
        'get', 'Use secrets', 'Get the value of a secret (the first match).',
        'get', action_get, configure_get,
        synopsis=('[-l LABEL] [-a KEY=VALUE]... [-c COLLECTION... | -A]',),
        description='Print the raw secret of the first secret matching -l/-a. With any --format but text the metadata '
                    'is included, and a non-UTF-8 secret is emitted as secret_base64.',
        aliases=('retrieve',),
        notes=('At least one of -l/--label or -a/--attribute is required.', 'Exits 1 when nothing matches.'),
        examples=(
            ('Print a secret', f'{PROG} get -a service=github -a username=me'),
            ('Use it in a script', f"TOKEN=$({PROG} get -l 'GitHub Token')"),
            ('Include metadata as JSON', f"{PROG} get -l 'GitHub Token' --format json"),
        ),
    ),
    Action(
        'exec', 'Use secrets', 'Execute a command with the chosen secret(s) injected into the environment.',
        'exec -- COMMAND [ARG...]', action_exec, configure_exec,
        synopsis=('[-l LABEL] [-a KEY=VALUE]... [-v VARIABLE] [-n] [-c COLLECTION... | -A] -- COMMAND [ARG...]',
                  '-m [-l LABEL] [-a KEY=VALUE]... [-p PREFIX] [--name-attribute KEY] [-n] '
                  '[-c COLLECTION... | -A] -- COMMAND [ARG...]'),
        description='Run COMMAND with the first secret matching -l/-a in an environment variable (-v, default '
                    'SECRET), or with every match in variables named after their labels (-m). The tool is replaced '
                    'by COMMAND, so nothing is printed and no secret is written anywhere else.',
        aliases=('run',),
        notes=("Put '--' before COMMAND so its own options are not parsed here.",
               'Secrets must be valid UTF-8 without NUL bytes.',
               'Exits 126 or 127 when COMMAND cannot be started or found; otherwise COMMAND decides the exit code.'),
        examples=(
            ('Run a command with one secret', f"{PROG} exec -l 'GitHub Token' -v GH_TOKEN -- gh api user"),
            ('Inject every secret of a service as PREFIX_LABEL', f'{PROG} exec -a service=aws -m -p AWS_ -- env'),
            ('Preview the variable names only', f'{PROG} exec -a service=aws -m --dry-run -- true'),
        ),
    ),
    Action(
        'set', 'Modify secrets', 'Create or overwrite a secret in a collection.',
        'set -l LABEL', action_set, configure_set,
        synopsis=('-l LABEL [-a KEY=VALUE]... [-c COLLECTION]',),
        description='Store a secret. The value is read from piped stdin, or prompted for twice without echo on a '
                    'terminal; it is never accepted as an argument. Replaces a secret with identical attributes.',
        aliases=('store',),
        notes=('-l/--label is required.',),
        examples=(
            ('Prompt securely for the value', f"{PROG} set -l 'GitHub Token' -a service=github -a username=me"),
            ('Store a file payload', f"{PROG} set -l 'Backup Config' -a type=file < config.json"),
            ('Store into a named collection', f"printf '%s' \"$TOKEN\" | {PROG} set -l Token -c vault"),
        ),
    ),
    Action(
        'update', 'Modify secrets', 'Update the value and/or attributes of secrets in a collection.',
        'update', action_update, configure_update,
        synopsis=('[-l LABEL] [-a KEY=VALUE]... [--new-label LABEL] [--add-attribute KEY=VALUE]... '
                  '[--remove-attribute KEY]... [--value] [-n] [-y] [-c COLLECTION... | -A]',),
        description='Change the label, attributes and/or value of every secret matching -l/-a. Matches are listed and '
                    'confirmed first unless -y is given. A new value is read like set reads it.',
        aliases=('upd', 'put'),
        notes=('At least one of -l/--label or -a/--attribute selects the secrets.',
               'At least one of --new-label, --add-attribute, --remove-attribute or --value says what to change.',
               'Without a terminal, -y/--yes is required.'),
        examples=(
            ('Rotate a secret (prompts for the new value)', f"{PROG} update -l 'GitHub Token' --value"),
            ('Relabel and tag', f"{PROG} update -l 'GH' --new-label 'GitHub Token' --add-attribute env=prod"),
            ('Preview an attribute removal', f'{PROG} update -a service=old --remove-attribute stale --dry-run'),
        ),
    ),
    Action(
        'delete', 'Modify secrets', 'Delete matched secrets in a collection.',
        'delete', action_delete, configure_delete,
        synopsis=('[-l LABEL] [-a KEY=VALUE]... [-n] [-y] [-c COLLECTION... | -A]',),
        description='Delete every secret matching -l/-a. Matches are listed and confirmed first unless -y is given.',
        aliases=('del', 'rm'),
        notes=('At least one of -l/--label or -a/--attribute is required.',
               'Without a terminal, -y/--yes is required.'),
        examples=(
            ('Preview what would be deleted', f'{PROG} delete -a service=github --dry-run'),
            ('Delete without prompting', f"{PROG} delete -l 'Old Token' -y"),
        ),
    ),
    Action(
        'move', 'Modify secrets', 'Move matched secrets to another collection, optionally relabelling them.',
        'move -t COLLECTION', action_move, configure_move,
        synopsis=('-t COLLECTION [-l LABEL] [-a KEY=VALUE]... [--new-label LABEL] [--replace] [-n] [-y] [-c COLLECTION... | -A]',),
        description='Copy every secret matching -l/-a into the destination collection with its label, attributes '
                    'and content type (or the --new-label), verify the copy, then delete the original. Matches are confirmed first '
                    'unless -y is given. Creation and modification times are not preserved.',
        aliases=('mv',),
        notes=('At least one of -l/--label or -a/--attribute is required.',
               'Refuses when the destination already holds a secret with the same attributes, unless --replace.',
               'Without a terminal, -y/--yes is required.'),
        examples=(
            ('Preview a move', f"{PROG} move -c login -t work -l 'GitHub token' --dry-run"),
            ('Move and rename', f"{PROG} mv -c login -t work -l 'GitHub token' --new-label 'GH work token'"),
            ('Move everything for a service', f'{PROG} mv -c login -t work -a service=github -y'),
        ),
    ),
    Action(
        'describe', 'Manage collections', 'List and search collections with their metadata (never their secrets).',
        'describe [QUERY]', action_describe, configure_describe,
        synopsis=('[-e] [QUERY]',),
        description='Show every collection (or those whose label, alias or path name matches QUERY) with its path, '
                    'aliases, lock state, number of secrets and timestamps. It never unlocks anything and never '
                    'prints a secret.',
        aliases=('cols', 'collections'),
        notes=('Exits 1 when a QUERY matches nothing.',),
        examples=(
            ('Show every collection', f'{PROG} describe'),
            ('Find a collection and emit it as HCL', f'{PROG} describe login --format hcl'),
        ),
    ),
    Action(
        'create', 'Manage collections', 'Create a new collection.',
        'create -c COLLECTION', action_create, configure_create,
        synopsis=('-c COLLECTION [--alias ALIAS]',),
        description='Create an empty collection (the desktop keyring may prompt for its password).',
        aliases=('new',),
        notes=('-c/--collection is required.',),
        examples=(('Create a collection', f'{PROG} create -c vault'),),
    ),
    Action(
        'destroy', 'Manage collections', 'Delete a collection.',
        'destroy -c COLLECTION...', action_destroy, configure_destroy,
        synopsis=('-c COLLECTION... [-n] [-y]',),
        description='Permanently delete collections and every secret in them. Confirmed first unless -y is given.',
        aliases=('erase',),
        notes=('-c/--collection is required.', 'This cannot be undone.', 'Without a terminal, -y/--yes is required.'),
        examples=(
            ('Preview', f'{PROG} destroy -c vault --dry-run'),
            ('Destroy without prompting', f'{PROG} destroy -c vault -y'),
        ),
    ),
    Action(
        'lock', 'Manage collections', 'Lock a collection.',
        'lock', action_lock, configure_lock,
        synopsis=('[-c COLLECTION... | -A]',),
        description='Lock collections persistently. Other actions restore the lock state they found; this one '
                    'changes it.',
        examples=(('Lock the default collection', f'{PROG} lock'), ('Lock everything', f'{PROG} lock -A')),
    ),
    Action(
        'unlock', 'Manage collections', 'Unlock a collection.',
        'unlock', action_unlock, configure_lock,
        synopsis=('[-c COLLECTION... | -A]',),
        description='Unlock collections persistently (may prompt via the desktop keyring).',
        examples=(('Unlock a named collection', f'{PROG} unlock -c login'),),
    ),
    Action(
        'help', 'Help', 'Display help docs, scoped optionally to an action.',
        'help [ACTION]', action_help, configure_help,
        synopsis=('[ACTION]',),
        examples=(('Help for one action', f'{PROG} help set'),),
    ),
    Action(
        'completion', 'Help', 'Generate a shell completion script.',
        'completion [SHELL]', action_completion, configure_completion,
        synopsis=('[bash | zsh | fish]',),
        description='Print a completion script for actions, aliases and options, generated from the same definitions '
                    'as this help. SHELL defaults to the one named by $SHELL.',
        notes=('The script is written to stdout; nothing is installed.',),
        examples=(
            ('Enable completion in the current bash session', f'eval "$({PROG} completion bash)"'),
            ('Install it for zsh', f'{PROG} completion zsh > ~/.zfunc/_{PROG}'),
            ('Install it for fish', f'{PROG} completion fish > ~/.config/fish/completions/{PROG}.fish'),
        ),
    ),
)
ACTION_BY_NAME = {name: action for action in ACTIONS for name in (action.name, *action.aliases)}


class Parser(argparse.ArgumentParser):
    """ArgumentParser that raises UsageError instead of printing its own usage and exiting."""

    def error(self, message: str):
        raise UsageError(message.split(' (choose from')[0])


def add_global_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('-h', '--help', action='store_true', help='Show this help message and exit.')
    parser.add_argument('--format', choices=FORMATS, metavar='FORMAT', default='text',
                        help='Output format: text (pretty, the default), table, json, hcl, md or csv.')
    parser.add_argument('--color', dest='color', action='store_const', const=True, default=None,
                        help='Force colored output (default: only when writing to a terminal).')
    parser.add_argument('--no-color', dest='color', action='store_const', const=False, default=None,
                        help='Disable colored output.')
    parser.add_argument('--pager', dest='pager', action='store_const', const=True, default=None,
                        help='Page long output through $PAGER (default: only when writing to a terminal).')
    parser.add_argument('--no-pager', dest='pager', action='store_const', const=False, default=None,
                        help='Never use a pager.')


def build_parser() -> tuple[argparse.ArgumentParser, dict[str, argparse.ArgumentParser]]:
    """One parser for the global options alone, plus one per action (each also accepting the global options)."""
    top = Parser(prog=PROG, add_help=False, allow_abbrev=False)
    add_global_options(top)
    top.set_defaults(action_name=None, handler=None)
    parsers = {}
    for action in ACTIONS:
        child = Parser(prog=f'{PROG} {action.name}', add_help=False, allow_abbrev=False)
        action.configure(child)
        add_global_options(child)
        child.set_defaults(action_name=action.name, handler=action.handler)
        parsers[action.name] = child
    for parser in (top, *parsers.values()):
        parser.set_defaults(parser=top, parsers=parsers)
    return top, parsers


def takes_value(arg: str, value_options: frozenset[str]) -> bool:
    """True when the option token consumes the next argv entry as its value (not --opt=value or -ovalue)."""
    if arg.startswith('--'):
        return '=' not in arg and arg in value_options
    for position, char in enumerate(arg[1:], 1):
        if f'-{char}' in value_options:
            return position == len(arg) - 1
    return False


def find_action(argv: list[str], value_options: frozenset[str]) -> int | None:
    """Index of the first argument naming an action, skipping options and their values; None before '--' ends."""
    skip = False
    for index, arg in enumerate(argv):
        if skip:
            skip = False
        elif arg == '--':
            return None
        elif arg.startswith('-') and arg != '-':
            skip = takes_value(arg, value_options)
        elif arg in ACTION_BY_NAME:
            return index
    return None


def parse_action_line(argv: list[str], top: argparse.ArgumentParser,
                      parsers: dict[str, argparse.ArgumentParser]) -> argparse.Namespace:
    """Options and arguments may sit before or after ACTION: pull the action word out, parse the rest with it."""
    value_options = frozenset(
        flag for parser in (top, *parsers.values()) for act in parser._actions if act.nargs != 0
        for flag in act.option_strings
    )
    index = find_action(argv, value_options)
    if index is not None:
        action = ACTION_BY_NAME[argv[index]]
        return parsers[action.name].parse_args(argv[:index] + argv[index + 1:])
    args, extra = top.parse_known_args(argv)
    if extra:
        word = extra[0]
        raise UsageError(f"Unrecognized option '{word}'." if word.startswith('-') else f"Unknown action '{word}'.")
    if argv and not args.help:
        raise UsageError('Missing ACTION.')
    return args


def term_width() -> int:
    return min(max(shutil.get_terminal_size().columns, 60), 100)


def table(entries: list[tuple[str, str, list[tuple[str, tuple[str, ...]]]]], style: Styler, indent: int = 4,
          cap: int = 28, gap: int = 3, column: int | None = None) -> list[str]:
    """Two-column definition list; entries are (plain name, styled name, [(description line, styles)...])."""
    column = column or min(max(len(plain) for plain, _, _ in entries) + gap, cap)
    room = max(term_width() - indent - column, 20)
    lines = []
    for plain, styled, description in entries:
        wrapped = [(line, styles) for text, styles in description for line in textwrap.wrap(text, room) or ['']]
        lead = ' ' * indent + styled + ' ' * (column - len(plain))
        if len(plain) + gap > column:
            lines.append(' ' * indent + styled)
            lead = ' ' * (indent + column)
        for number, (line, styles) in enumerate(wrapped):
            lines.append((lead if number == 0 else ' ' * (indent + column)) + style(line, *styles))
    return lines


def option_entries(parser: argparse.ArgumentParser, style: Styler, global_ones: bool) -> list:
    entries = []
    for action in parser._actions:
        if not action.option_strings or (action.dest in GLOBAL_DESTS) != global_ones:
            continue
        flags = ', '.join(action.option_strings)
        metavar = (action.metavar or action.dest.upper()) if action.nargs != 0 else ''
        plain = f'{flags} {metavar}'.strip()
        styled = style(flags, 'cyan') + (f" {style(metavar, 'yellow')}" if metavar else '')
        entries.append((plain, styled, [(action.help or '', ())]))
    return entries


def positional_entries(parser: argparse.ArgumentParser, style: Styler) -> list:
    return [
        (name, style(name, 'yellow'), [(action.help or '', ())])
        for action in parser._actions
        if not action.option_strings
        for name in [(action.metavar or action.dest).upper()]
    ]


def paragraph(text: str, indent: int = 4) -> list[str]:
    return [' ' * indent + line for line in textwrap.wrap(text, term_width() - indent)]


def section(title: str, body: list[str], style: Styler) -> list[str]:
    return [style(title, 'bold'), *body, '']


def example_lines(examples: tuple[tuple[str, str], ...], style: Styler) -> list[str]:
    lines = []
    for number, (comment, command) in enumerate(examples):
        lines += ([''] if number else []) + [f"    {style(f'# {comment}', 'green')}", f'    {command}']
    return lines


SYNOPSIS_TOKEN = re.compile(r'(?P<option>--?[A-Za-z][\w-]*)|(?P<placeholder>\b[A-Z][A-Z_]*\b)')


def style_synopsis(text: str, style: Styler) -> str:
    return SYNOPSIS_TOKEN.sub(lambda m: style(m.group(), 'cyan' if m.group('option') else 'yellow'), text)


def bullets(texts: tuple[str, ...] | list[str], indent: int) -> list[str]:
    return [
        line
        for text in texts
        for line in textwrap.wrap(text, term_width(), initial_indent=' ' * indent + '- ',
                                  subsequent_indent=' ' * (indent + 2))
    ]


def synopsis_lines(actions: tuple[Action, ...], style: Styler) -> list[str]:
    """One manpage-style line per usage of each action; [ ] optional, ... repeatable, | alternatives."""
    lines = []
    for action in actions:
        head = f'{PROG} {action.name}'
        for tail in action.synopsis:
            wrapped = textwrap.wrap(f'{head} {tail}', term_width() - 4, subsequent_indent=' ' * 4,
                                    break_long_words=False, break_on_hyphens=False)
            lines.append('    ' + style(head, 'bold') + style_synopsis(wrapped[0][len(head):], style))
            lines += ['    ' + style_synopsis(line, style) for line in wrapped[1:]]
    return lines


def argument_sections(parsers: dict[str, argparse.ArgumentParser], style: Styler) -> list[str]:
    """A sub-section per action: what it does, then every argument and option it accepts."""
    lines = [
        f"    {style('ACTION', 'bold', 'yellow')}",
        *paragraph('Operation to run: an action name or alias from ACTIONS. The first argument naming an action is '
                   'the action; every other option or argument belongs to it and may come before or after it.',
                   indent=8),
        '',
    ]
    for action in ACTIONS:
        aliases = f" ({', '.join(action.aliases)})" if action.aliases else ''
        lines.append(f"    {style(action.name, 'bold', 'cyan')}{style(aliases, 'dim')}")
        lines += paragraph(action.description or action.summary, indent=8)
        parser = parsers[action.name]
        entries = positional_entries(parser, style) + option_entries(parser, style, False)
        if entries:
            lines += ['', *table(entries, style, indent=8)]
        if action.notes:
            lines += ['', *bullets(action.notes, indent=8)]
        lines.append('')
    return lines[:-1]


def note_sections(style: Styler) -> list[str]:
    groups = (
        ('Command line', (
            'Options and arguments may be given in any order, before or after ACTION.',
            'The first argument that names an action (or alias) is the action; use -- to stop option parsing, '
            'which exec needs before its COMMAND.',
            f"Run '{PROG} help ACTION' or '{PROG} ACTION -h' for one action.",
        )),
        ('Secret values', (
            'Only get and exec reveal secrets (get prints one, exec injects them into a process); list and describe '
            'show metadata only.',
            'set and update --value read the secret from piped stdin or prompt twice without echo; a secret is '
            'never an argument.',
        )),
        ('Collections and locking', (
            'Collections are matched by label, alias or D-Bus path name; the default collection is used unless '
            '-c or -A is given.',
            'A collection this tool had to unlock is locked again on exit, also on errors, Ctrl-C, SIGTERM and '
            'SIGHUP. lock and unlock change the state persistently.',
            'destroy cannot be undone.',
        )),
        ('Output', (
            '--format text (default) is pretty-printed for people; table is a boxed table as wide as the terminal; '
            'json prints an array of records; hcl prints one HCL2 block per record; md prints a markdown table; '
            'csv prints a header row plus one row per record.',
            'Color and paging default to on only when writing to a terminal (NO_COLOR is honored); the pager is '
            '$PAGER (default: less) and is never used for get.',
        )),
    )
    lines = []
    for title, notes in groups:
        lines += [f"    {style(title, 'bold', 'dim')}", *bullets(notes, indent=8), '']
    return lines[:-1]


def render_top_help(parser: argparse.ArgumentParser, parsers: dict[str, argparse.ArgumentParser],
                    style: Styler) -> str:
    lines = section('USAGE', [f'    {PROG} [OPTION...] <ACTION> [ARGUMENT...]'], style)
    lines += section('SUMMARY', paragraph(
        'Manage secrets and collections in the system secrets manager (freedesktop Secret Service: GNOME Keyring, '
        'KWallet, ...). Not a drop-in replacement for secret-tool(1).'), style)
    lines += section('SYNOPSIS', synopsis_lines(ACTIONS, style), style)
    lines += section('OPTIONS', table(option_entries(parser, style, True), style), style)

    body = []
    for group in GROUPS:
        body.append(f"    {style(group, 'bold', 'dim')}")
        entries = []
        for action in (a for a in ACTIONS if a.group == group):
            description = [(action.summary, ())]
            if action.aliases:
                description.append((f"Aliases: {', '.join(action.aliases)}.", ('dim',)))
            entries.append((action.name, style(action.name, 'cyan'), description))
        body += table(entries, style, indent=8, column=max(len(a.name) for a in ACTIONS) + 3) + ['']
    lines += section('ACTIONS', body[:-1], style)
    lines += section('ARGUMENTS', argument_sections(parsers, style), style)
    lines += section('NOTES', note_sections(style), style)
    lines += section('EXIT CODES', table([
        ('0', '0', [('OK.', ())]),
        ('1', '1', [('No match, or a Secret Service or runtime error.', ())]),
        ('2', '2', [('Usage error.', ())]),
        ('126, 127', '126, 127', [('exec could not run, or find, its COMMAND.', ())]),
    ], style, cap=12, gap=4), style)
    lines += section('EXAMPLES', example_lines((
        ('Show help for an action', f'{PROG} help set'),
        ('List every secret with metadata', f'{PROG} list'),
        ('Search all collections and show a table', f'{PROG} list token --all-collections --format table'),
        ('Store a secret (prompts without echo)', f"{PROG} set -l 'GitHub Token' -a service=github"),
        ('Print a secret', f'{PROG} get -a service=github'),
        ('Preview a deletion', f'{PROG} delete -a service=github --dry-run'),
        ('Run a command with a secret in its environment', f"{PROG} exec -l 'GitHub Token' -v GH_TOKEN -- gh api"),
        ('Rotate a secret', f"{PROG} update -l 'GitHub Token' --value"),
        ('Show the collections', f'{PROG} describe'),
        ('Create and unlock a collection', f'{PROG} create -c vault && {PROG} unlock -c vault'),
        ('Enable bash completion', f'eval "$({PROG} completion bash)"'),
    ), style), style)
    return '\n'.join(lines[:-1])


def render_action_help(action: Action, parser: argparse.ArgumentParser, style: Styler) -> str:
    lines = section('USAGE', [f'    {PROG} [OPTION...] {action.usage}'], style)
    summary = paragraph(action.description or action.summary)
    if action.aliases:
        aliases = ', '.join(action.aliases)
        summary += ['', f"    {style(f'Aliases: {aliases}.', 'dim')}"]
    lines += section('SUMMARY', summary, style)
    lines += section('SYNOPSIS', synopsis_lines((action,), style), style)
    positionals = positional_entries(parser, style)
    if positionals:
        lines += section('ARGUMENTS', table(positionals, style), style)
    local = option_entries(parser, style, False)
    if local:
        lines += section('OPTIONS', table(local, style), style)
    lines += section('GLOBAL OPTIONS', table(option_entries(parser, style, True), style), style)
    if action.notes:
        lines += section('NOTES', bullets(action.notes, indent=4), style)
    if action.examples:
        lines += section('EXAMPLES', example_lines(action.examples, style), style)
    return '\n'.join(lines[:-1])


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    top, parsers = build_parser()
    try:
        args = parse_action_line(argv, top, parsers)
    except UsageError as err:
        console = Console(color=scan_color_flag(argv))
        console.error(str(err))
        console.info(f"Try '{PROG} -h' or '{PROG} help ACTION' for usage.")
        return err.exit_code

    console = Console(args.format, args.color, args.pager)
    try:
        handler = action_help if args.help else args.handler or action_help
        return handler(args, console)
    except CliError as err:
        console.error(str(err))
        return err.exit_code
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    sys.exit(main())
