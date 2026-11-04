#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "aiohttp==3.12.13",
#     "beautifulsoup4==4.13.4",
# ]
# ///
"""Search Craigslist apartment rentals without the LLM agent.

Standalone port of the Craigslist search in rental_agent/tools/web_tools.py.
Run with: uv run ~/.junie/custom/scripts/find-housing/find_housing.py --city "san francisco"
"""

from __future__ import annotations

import argparse
import asyncio
import configparser
import json
import math
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from typing import Any
from urllib.parse import ParseResult, urlencode, urljoin, urlparse

try:
    import aiohttp
    from bs4 import BeautifulSoup, NavigableString, Tag
except ImportError:  # plain python3 without the PEP 723 deps: main() re-runs the script under uv
    aiohttp = None

REQUEST_TIMEOUT_SECONDS = 30
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
SEARCH_RESULTS_CONTAINER_SELECTOR = '.cl-static-search-results'
SEARCH_RESULT_SELECTOR = 'li.cl-static-search-result'
POSTING_BODY_SELECTOR = '#postingbody'
DETAIL_CONCURRENCY = 4
UV_REEXEC_ENV = 'FIND_HOUSING_UV_REEXEC'
CONFIG_SECTION = 'find_housing'
CONFIG_FILE_PARTS = ('.config', 'find_housing.cfg')
DEFAULT_MAX_LISTINGS = 10
DEFAULT_FORMAT = 'table'
FORMAT_CHOICES = ('table', 'json')
CONFIG_NUMBER_TYPES = {
    'max_rent': int,
    'min_bedrooms': int,
    'max_bedrooms': int,
    'min_bathrooms': float,
    'max_bathrooms': float,
    'max_listings': int,
}
CONFIG_KEYS = frozenset({*CONFIG_NUMBER_TYPES, 'city', 'query', 'details', 'format'})
DEFAULT_PORTS = {'http': 80, 'https': 443}
SKIPPED_TAGS = frozenset({'script', 'style'})
BLOCK_TAGS = frozenset({
    'address', 'article', 'aside', 'blockquote', 'dd', 'div', 'dl', 'dt', 'fieldset', 'figcaption', 'figure',
    'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre',
    'section', 'table', 'tr', 'ul',
})

CRAIGSLIST_CITY_MAPPINGS = {
    'new york': 'newyork',
    'los angeles': 'losangeles',
    'chicago': 'chicago',
    'houston': 'houston',
    'phoenix': 'phoenix',
    'philadelphia': 'philadelphia',
    'san antonio': 'sanantonio',
    'san diego': 'sandiego',
    'dallas': 'dallas',
    'san jose': 'sanjose',
    'austin': 'austin',
    'jacksonville': 'jacksonville',
    'fort worth': 'fortworth',
    'columbus': 'columbus',
    'charlotte': 'charlotte',
    'san francisco': 'sfbay',
    'indianapolis': 'indianapolis',
    'seattle': 'seattle',
    'denver': 'denver',
    'washington': 'washingtondc',
    'boston': 'boston',
    'el paso': 'elpaso',
    'nashville': 'nashville',
    'detroit': 'detroit',
    'oklahoma city': 'oklahomacity',
    'portland': 'portland',
    'las vegas': 'lasvegas',
    'memphis': 'memphis',
    'louisville': 'louisville',
    'baltimore': 'baltimore',
    'milwaukee': 'milwaukee',
    'albuquerque': 'albuquerque',
    'tucson': 'tucson',
    'fresno': 'fresno',
    'sacramento': 'sacramento',
    'atlanta': 'atlanta',
    'kansas city': 'kansascity',
    'long beach': 'longbeach',
    'colorado springs': 'cosprings',
    'raleigh': 'raleigh',
    'miami': 'miami',
    'virginia beach': 'norfolk',
    'omaha': 'omaha',
    'oakland': 'sfbay',
    'minneapolis': 'minneapolis',
    'tulsa': 'tulsa',
    'arlington': 'dallas',
    'tampa': 'tampa',
    'new orleans': 'neworleans',
    'wichita': 'wichita',
    'cleveland': 'cleveland',
    'bakersfield': 'bakersfield',
    'aurora': 'denver',
    'anaheim': 'orangecounty',
    'honolulu': 'honolulu',
    'santa ana': 'orangecounty',
    'corpus christi': 'corpuschristi',
    'riverside': 'inlandempire',
    'lexington': 'lexington',
    'stockton': 'stockton',
    'henderson': 'lasvegas',
    'saint paul': 'twincities',
    'st. louis': 'stlouis',
    'st louis': 'stlouis',
    'cincinnati': 'cincinnati',
    'pittsburgh': 'pittsburgh',
    'anchorage': 'anchorage',
    'greensboro': 'greensboro',
    'plano': 'dallas',
    'newark': 'newjersey',
    'lincoln': 'lincoln',
    'orlando': 'orlando',
    'durham': 'raleigh',
    'chula vista': 'sandiego',
    'jersey city': 'newjersey',
    'chandler': 'phoenix',
    'madison': 'madison',
    'laredo': 'laredo',
    'lubbock': 'lubbock',
    'scottsdale': 'phoenix',
    'reno': 'reno',
    'buffalo': 'buffalo',
    'gilbert': 'phoenix',
    'glendale': 'phoenix',
    'north las vegas': 'lasvegas',
    'winston-salem': 'winstonsalem',
    'chesapeake': 'norfolk',
    'norfolk': 'norfolk',
    'fremont': 'sfbay',
    'garland': 'dallas',
    'irvine': 'orangecounty',
    'hialeah': 'miami',
    'richmond': 'richmond',
    'boise': 'boise',
    'spokane': 'spokane',
    'baton rouge': 'batonrouge',
    'tacoma': 'seattle',
    'san bernardino': 'inlandempire',
    'grand rapids': 'grandrapids',
    'huntsville': 'huntsville',
    'salt lake city': 'saltlakecity',
    'modesto': 'modesto',
    'fontana': 'inlandempire',
    'worcester': 'boston',
    'des moines': 'desmoines',
    'oxnard': 'ventura',
    'fayetteville': 'fayetteville',
    'moreno valley': 'inlandempire',
    'rochester': 'rochester',
    'huntington beach': 'orangecounty',
    'knoxville': 'knoxville',
    'akron': 'akron',
    'little rock': 'littlerock',
    'augusta': 'augusta',
    'port st. lucie': 'treasurecoast',
    'grand prairie': 'dallas',
    'overland park': 'kansascity',
    'tallahassee': 'tallahassee',
    'tempe': 'phoenix',
    'dayton': 'dayton',
    'sioux falls': 'siouxfalls',
    'springfield': 'springfield',
    'peoria': 'peoria',
    'provo': 'saltlakecity',
    'elgin': 'chicago',
    'west valley city': 'saltlakecity',
    'waco': 'waco',
    'north charleston': 'charleston',
    'santa clarita': 'losangeles',
    'ann arbor': 'annarbor',
    'beaumont': 'beaumont',
    'fort lauderdale': 'miami',
    'mcallen': 'mcallen',
    'cedar rapids': 'cedarrapids',
    'charleston': 'charleston',
    'vallejo': 'sfbay',
    'palm bay': 'spacecoast',
    'columbia': 'columbia',
    'el monte': 'losangeles',
    'aberdeen': 'aberdeen',
    'annapolis': 'annapolis',
    'bend': 'bend',
    'boulder': 'boulder',
    'burlington': 'burlington',
    'champaign': 'champaign',
    'corvallis': 'corvallis',
    'davis': 'sacramento',
    'eugene': 'eugene',
    'flagstaff': 'flagstaff',
    'fort collins': 'fortcollins',
    'gainesville': 'gainesville',
    'ithaca': 'ithaca',
    'lafayette': 'lafayette',
    'lawrence': 'lawrence',
    'manhattan': 'manhattan',
    'missoula': 'missoula',
    'morgantown': 'morgantown',
    'mount pleasant': 'charleston',
    'northampton': 'westernmass',
    'pensacola': 'pensacola',
    'pocatello': 'pocatello',
    'pullman': 'pullman',
    'roanoke': 'roanoke',
    'san luis obispo': 'slo',
    'santa barbara': 'santabarbara',
    'santa cruz': 'santacruz',
    'savannah': 'savannah',
    'state college': 'pennstate',
    'tuscaloosa': 'tuscaloosa',
    'tyler': 'tyler',
    'valdosta': 'valdosta',
    'wichita falls': 'wichitafalls',
    'wilmington': 'wilmington',
    'winchester': 'winchester',
    'york': 'york',
    'youngstown': 'youngstown',
    'yuma': 'yuma',
}


@dataclass
class Listing:
    title: str | None
    url: str | None
    rent: int | None
    location: str | None
    bedrooms: int | None
    bathrooms: float | None
    body: str | None = None


class FetchError(Exception):
    """Raised when the Craigslist search request fails, returns an empty page, or returns unexpected markup."""


def craigslist_subdomain(city: str) -> str:
    """Map a city name to its Craigslist subdomain, falling back to the name without spaces."""
    name = ' '.join(city.lower().split())
    return CRAIGSLIST_CITY_MAPPINGS.get(name, re.sub(r'[^a-z0-9]', '', name))


def build_search_url(
    city: str,
    *,
    max_rent: int | None = None,
    min_bedrooms: int | None = None,
    max_bedrooms: int | None = None,
    min_bathrooms: float | None = None,
    max_bathrooms: float | None = None,
    query: str | None = None,
) -> str:
    """Build a Craigslist apartment search URL with URL-encoded parameters."""
    base_url = f'https://{craigslist_subdomain(city)}.craigslist.org/search/apa'
    params: list[tuple[str, str]] = []

    if max_rent and max_rent > 0:
        params.append(('max_price', str(int(max_rent))))
    if min_bedrooms and min_bedrooms > 0:
        params.append(('min_bedrooms', str(min_bedrooms)))
    if max_bedrooms and max_bedrooms > 0:
        params.append(('max_bedrooms', str(max_bedrooms)))
    if min_bathrooms and min_bathrooms > 0:
        params.append(('min_bathrooms', f'{min_bathrooms:g}'))
    if max_bathrooms and max_bathrooms > 0:
        params.append(('max_bathrooms', f'{max_bathrooms:g}'))
    if query and query.strip():
        params.append(('query', query.strip()))

    params.extend([('availabilityMode', '0'), ('sale_date', 'all dates'), ('sort', 'date')])
    return f'{base_url}?{urlencode(params)}'


def _text(tag: Tag | None) -> str | None:
    if tag is None:
        return None
    text = ' '.join(tag.get_text(' ').split())
    return text or None


def _parse_rent(text: str | None) -> int | None:
    if not text:
        return None
    match = re.search(r'\$\s*([\d,]+)', text)
    return int(match.group(1).replace(',', '')) if match else None


def _parse_housing(text: str | None) -> tuple[int | None, float | None]:
    """Parse bedrooms and bathrooms from text like '2br / 1ba' or '2 bed/1 bath'. Studio counts as 0 bedrooms."""
    if not text:
        return None, None
    bedrooms: int | None = None
    if re.search(r'\bstudio\b', text, re.IGNORECASE):
        bedrooms = 0
    br_match = re.search(r'(\d+)[\s-]*(?:bedrooms?|bdrms?|beds?|br|bd)(?![a-z])', text, re.IGNORECASE)
    if br_match:
        bedrooms = int(br_match.group(1))
    ba_match = re.search(r'(\d+(?:\.\d+)?)[\s-]*(?:bathrooms?|baths?|bth|ba)(?![a-z])', text, re.IGNORECASE)
    bathrooms = float(ba_match.group(1)) if ba_match else None
    return bedrooms, bathrooms


def _parse_card(card: Tag) -> Listing:
    link = card.find('a', href=True)
    url = str(link['href']) if link else None
    title = _text(card.select_one('.title')) or (str(card.get('title')) if card.get('title') else None)
    housing = _text(card.select_one('.housing')) or _text(card.select_one('.meta'))
    bedrooms, bathrooms = _parse_housing(housing or title)
    location = (_text(card.select_one('.location')) or '').strip('() ') or None
    return Listing(
        title=title,
        url=url,
        rent=_parse_rent(_text(card.select_one('.price'))),
        location=location,
        bedrooms=bedrooms,
        bathrooms=bathrooms,
    )


def parse_search_results(html: str, limit: int) -> list[Listing]:
    """Parse Craigslist search result cards into structured listings, keeping at most `limit`."""
    soup = BeautifulSoup(html, 'html.parser')
    return [_parse_card(card) for card in soup.select(SEARCH_RESULT_SELECTOR)[:limit]]


async def _get_text(session: aiohttp.ClientSession, url: str) -> str:
    """GET a page and return its text, raising FetchError on network, HTTP, timeout, or decode failures."""
    try:
        async with session.get(url) as response:
            response.raise_for_status()
            return await response.text()
    except UnicodeDecodeError as err:
        raise FetchError(f'response from {url} could not be decoded: {err}') from err
    except (aiohttp.ClientError, asyncio.TimeoutError) as err:
        reason = type(err).__name__ + (f': {err}' if str(err) else '')
        raise FetchError(f'request to {url} failed ({reason})') from err


async def fetch_search_page(session: aiohttp.ClientSession, url: str) -> str:
    """Fetch a search results page, raising FetchError on network, HTTP, or empty-response failures."""
    html = await _get_text(session, url)
    if not html.strip():
        raise FetchError(f'empty response from {url}')
    markers = f'{SEARCH_RESULTS_CONTAINER_SELECTOR}, {SEARCH_RESULT_SELECTOR}'
    if BeautifulSoup(html, 'html.parser').select_one(markers) is None:
        raise FetchError(f'unexpected page markup from {url} (blocked, JS-only, or changed layout)')
    return html


def _collect_posting_text(node: Tag, parts: list[str]) -> None:
    for child in node.children:
        if isinstance(child, NavigableString):
            if type(child) is NavigableString:
                parts.append(re.sub(r'\s+', ' ', str(child)))
        elif child.name == 'br':
            parts.append('\n')
        elif child.name in BLOCK_TAGS:
            parts.append('\n')
            _collect_posting_text(child, parts)
            parts.append('\n')
        elif child.name not in SKIPPED_TAGS:
            _collect_posting_text(child, parts)


async def fetch_posting_body(session: aiohttp.ClientSession, url: str) -> str | None:
    """Return the #postingbody text of a posting page, or None when the element is missing or empty."""
    soup = BeautifulSoup(await _get_text(session, url), 'html.parser')
    posting = soup.select_one(POSTING_BODY_SELECTOR)
    if posting is None:
        return None

    for label in posting.select('.print-information'):
        label.decompose()

    parts: list[str] = []
    _collect_posting_text(posting, parts)
    lines = (' '.join(line.split()) for line in ''.join(parts).split('\n'))
    return '\n'.join(line for line in lines if line) or None


def _origin(parsed: ParseResult) -> tuple[str, str, int] | None:
    if parsed.scheme not in DEFAULT_PORTS or not parsed.hostname:
        return None
    port = parsed.port if parsed.port is not None else DEFAULT_PORTS[parsed.scheme]
    return parsed.scheme, parsed.hostname, port


def is_valid_detail_url(url: str, search_url: str) -> bool:
    """Allow the search page's own origin, or Craigslist hosts on default ports; reject credentials and backslashes."""
    try:
        target = urlparse(url)
        origin = _origin(target)
        search_origin = _origin(urlparse(search_url))
    except ValueError:
        return False
    if origin is None or target.username is not None or target.password is not None or re.search(r'[\\\s]', url):
        return False
    if origin == search_origin:
        return True
    host = origin[1]
    on_default_port = origin[2] == DEFAULT_PORTS[origin[0]]
    return on_default_port and (host == 'craigslist.org' or host.endswith('.craigslist.org'))


async def fetch_posting_bodies(session: aiohttp.ClientSession, listings: list[Listing], search_url: str) -> None:
    """Fill Listing.body for each listing with a URL, with at most DETAIL_CONCURRENCY requests in flight, failing fast."""
    semaphore = asyncio.Semaphore(DETAIL_CONCURRENCY)
    failed = False

    async def fill(listing: Listing) -> None:
        nonlocal failed
        if not listing.url:
            return
        try:
            full_url = urljoin(search_url, listing.url)
        except ValueError:
            full_url = ''
        if not is_valid_detail_url(full_url, search_url):
            print(f'skipping invalid detail URL: {listing.url}', file=sys.stderr)
            return
        async with semaphore:
            if failed:
                return
            try:
                listing.body = await fetch_posting_body(session, full_url)
            except Exception:
                failed = True
                raise

    try:
        async with asyncio.TaskGroup() as tg:
            for listing in listings:
                tg.create_task(fill(listing))
    except* Exception as group:
        error = group.exceptions[0]
        if isinstance(error, FetchError):
            raise error
        raise FetchError(f'unexpected error while fetching postings: {error!r}') from error


async def run_search(args: argparse.Namespace) -> list[Listing]:
    url = build_search_url(
        args.city,
        max_rent=args.max_rent,
        min_bedrooms=args.min_bedrooms,
        max_bedrooms=args.max_bedrooms,
        min_bathrooms=args.min_bathrooms,
        max_bathrooms=args.max_bathrooms,
        query=args.query,
    )
    print(f'searching {url}', file=sys.stderr)
    timeout = aiohttp.ClientTimeout(total=REQUEST_TIMEOUT_SECONDS)
    async with aiohttp.ClientSession(timeout=timeout, headers={'User-Agent': USER_AGENT}) as session:
        html = await fetch_search_page(session, url)
        listings = parse_search_results(html, args.max_listings)
        if args.details and listings:
            print(f'fetching {len(listings)} posting(s)', file=sys.stderr)
            await fetch_posting_bodies(session, listings, url)
    return listings


def _or_dash(value: Any) -> str:
    return '-' if value is None else str(value)


def format_table(listings: list[Listing], *, with_body: bool = False) -> str:
    if not listings:
        return 'No listings found.'
    headers = ['#', 'RENT', 'BR', 'BA', 'LOCATION', 'TITLE', 'URL']
    rows = [
        [
            str(index),
            _or_dash(f'${listing.rent:,}' if listing.rent is not None else None),
            _or_dash(listing.bedrooms),
            _or_dash(f'{listing.bathrooms:g}' if listing.bathrooms is not None else None),
            _or_dash(listing.location),
            _or_dash(listing.title),
            _or_dash(listing.url),
        ]
        for index, listing in enumerate(listings, start=1)
    ]
    widths = [max(len(row[col]) for row in [headers, *rows]) for col in range(len(headers) - 1)]
    lines = []
    for row in [headers, *rows]:
        cells = [cell.ljust(widths[col]) for col, cell in enumerate(row[:-1])]
        lines.append('  '.join([*cells, row[-1]]).rstrip())
    table = '\n'.join(lines)
    if not with_body:
        return table
    bodies = [
        f'\n[{index}] {_or_dash(listing.title)}\n{listing.body or "(no posting body found)"}'
        for index, listing in enumerate(listings, start=1)
    ]
    return '\n'.join([table, *bodies])


def format_json(city: str, listings: list[Listing]) -> str:
    payload = {
        'city': city,
        'count': len(listings),
        'listings': [asdict(listing) for listing in listings],
    }
    return json.dumps(payload, indent=2)


class ConfigError(Exception):
    pass


def config_path() -> str:
    return os.path.expanduser(os.path.join('~', *CONFIG_FILE_PARTS))


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
        return value[1:-1].strip()
    return value


def _parse_config_value(key: str, raw: str) -> Any:
    if key == 'details':
        try:
            return configparser.ConfigParser.BOOLEAN_STATES[raw.strip().lower()]
        except KeyError:
            raise ConfigError(f'{key} must be yes/no, on/off, true/false or 1/0, got {raw!r}') from None
    value = _unquote(raw) if key in ('city', 'query', 'format') else raw.strip()
    if key == 'query':
        return value or None
    if key == 'format':
        if value not in FORMAT_CHOICES:
            raise ConfigError(f'format must be one of {", ".join(FORMAT_CHOICES)}, got {raw!r}')
        return value
    if key == 'city':
        if not value:
            raise ConfigError('city must not be empty')
        if not craigslist_subdomain(value):
            raise ConfigError('city must contain at least one letter or digit')
        return value
    try:
        number = CONFIG_NUMBER_TYPES[key](value)
    except ValueError:
        raise ConfigError(f'{key} must be a number, got {raw!r}') from None
    if key == 'max_listings':
        if number < 1:
            raise ConfigError('max_listings must be at least 1')
    elif not 0 <= number < math.inf:
        raise ConfigError(f'{key} must be a non-negative number, got {raw!r}')
    return number


def load_config(path: str) -> dict[str, Any]:
    if not os.path.exists(path):
        return {}
    parser = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=('#', ';'))
    try:
        with open(path, encoding='utf-8') as handle:
            parser.read_file(handle, source=path)
    except (OSError, UnicodeDecodeError) as err:
        raise ConfigError(f'cannot read config {path}: {err}') from None
    except configparser.Error as err:
        raise ConfigError(f'invalid config file: {err}') from None
    if parser.defaults():
        raise ConfigError(f'{path}: keys must be inside [{CONFIG_SECTION}]')
    unknown_sections = [name for name in parser.sections() if name != CONFIG_SECTION]
    if unknown_sections:
        raise ConfigError(f'{path}: unknown section [{unknown_sections[0]}], expected [{CONFIG_SECTION}]')
    if not parser.has_section(CONFIG_SECTION):
        return {}
    values: dict[str, Any] = {}
    try:
        for key, raw in parser.items(CONFIG_SECTION):
            if key not in CONFIG_KEYS:
                raise ConfigError(f'unknown key {key!r} in [{CONFIG_SECTION}]')
            values[key] = _parse_config_value(key, raw)
        for low, high in (('min_bedrooms', 'max_bedrooms'), ('min_bathrooms', 'max_bathrooms')):
            if low in values and high in values and values[low] > values[high]:
                raise ConfigError(f'{low} must not exceed {high}')
    except ConfigError as err:
        raise ConfigError(f'{path}: {err}') from None
    return values


def apply_config(args: argparse.Namespace, config: dict[str, Any], path: str = '') -> None:
    cli_keys = {key for key in CONFIG_KEYS if getattr(args, key, None) is not None}
    for key, value in config.items():
        if key not in cli_keys:
            setattr(args, key, value)
    for low, high in (('min_bedrooms', 'max_bedrooms'), ('min_bathrooms', 'max_bathrooms')):
        low_value, high_value = getattr(args, low), getattr(args, high)
        if low_value is None or high_value is None or low_value <= high_value:
            continue
        if (low in cli_keys) == (high in cli_keys):
            continue  # same source: config conflicts are caught by load_config, CLI ones by validate_args
        from_config, from_cli = (high, low) if low in cli_keys else (low, high)
        raise ConfigError(
            f'{from_config} = {getattr(args, from_config)} from {path} conflicts with '
            f'--{from_cli.replace("_", "-")} {getattr(args, from_cli)} '
            f'(min must not exceed max; the CLI value wins for the same key, nothing is dropped)'
        )
    if args.max_listings is None:
        args.max_listings = DEFAULT_MAX_LISTINGS
    if args.format is None:
        args.format = DEFAULT_FORMAT
    if args.details is None:
        args.details = False


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='find_housing.py',
        description='Search Craigslist apartment rentals without the LLM agent.',
    )
    parser.add_argument('--city', help='city name, e.g. "san francisco" (required unless set in the config file)')
    parser.add_argument('--max-rent', type=int, help='maximum monthly rent in USD')
    parser.add_argument('--min-bedrooms', type=int, help='minimum number of bedrooms')
    parser.add_argument('--max-bedrooms', type=int, help='maximum number of bedrooms')
    parser.add_argument('--min-bathrooms', type=float, help='minimum number of bathrooms')
    parser.add_argument('--max-bathrooms', type=float, help='maximum number of bathrooms')
    parser.add_argument('--query', help='free-text search, e.g. "dog friendly"')
    parser.add_argument('--max-listings', type=int, help='maximum number of results (default: 10)')
    parser.add_argument(
        '--details',
        action=argparse.BooleanOptionalAction,
        help='fetch each listing posting body (one request per listing); --no-details overrides the config file',
    )
    parser.add_argument('--format', choices=FORMAT_CHOICES, help='output format (default: table)')
    parser.add_argument(
        '--check-args',
        action='store_true',
        help='print the parsed arguments as JSON and exit 0 without network access',
    )
    return parser


def validate_args(parser: argparse.ArgumentParser, args: argparse.Namespace) -> None:
    if args.city is None:
        parser.error(f'--city is required (or set city in [{CONFIG_SECTION}] of {config_path()})')
    if not args.city.strip():
        parser.error('--city must not be empty')
    if not craigslist_subdomain(args.city):
        parser.error('--city must contain at least one letter or digit')
    for flag, value in (
        ('--max-rent', args.max_rent),
        ('--min-bedrooms', args.min_bedrooms),
        ('--max-bedrooms', args.max_bedrooms),
        ('--min-bathrooms', args.min_bathrooms),
        ('--max-bathrooms', args.max_bathrooms),
    ):
        if value is not None and not 0 <= value < math.inf:
            parser.error(f'{flag} must be a non-negative number')
    if args.max_listings is not None and args.max_listings < 1:
        parser.error('--max-listings must be at least 1')
    if args.min_bedrooms is not None and args.max_bedrooms is not None and args.min_bedrooms > args.max_bedrooms:
        parser.error('--min-bedrooms must not exceed --max-bedrooms')
    if args.min_bathrooms is not None and args.max_bathrooms is not None and args.min_bathrooms > args.max_bathrooms:
        parser.error('--min-bathrooms must not exceed --max-bathrooms')


def reexec_with_uv(argv: list[str]) -> int:
    if os.environ.get(UV_REEXEC_ENV):
        print('error: aiohttp and beautifulsoup4 are unavailable even under uv run', file=sys.stderr)
        return 1
    env = {**os.environ, UV_REEXEC_ENV: '1'}
    cmd = ['uv', 'run', '--quiet', os.path.abspath(__file__), *argv]
    try:
        completed = subprocess.run(cmd, env=env, check=False)
    except OSError as err:
        print(f'error: aiohttp and beautifulsoup4 missing and uv could not start ({err})', file=sys.stderr)
        return 1
    if completed.returncode == 2:
        print('error: could not resolve aiohttp and beautifulsoup4 via uv run (uv exited 2)', file=sys.stderr)
    return 0 if completed.returncode == 0 else 1


def main(argv: list[str] | None = None) -> int:
    forwarded = sys.argv[1:] if argv is None else list(argv)
    parser = build_parser()
    args = parser.parse_args(forwarded)
    try:
        config = load_config(config_path())
        apply_config(args, config, config_path())
    except ConfigError as err:
        parser.error(str(err))
    validate_args(parser, args)

    if args.check_args:
        print(json.dumps(vars(args), indent=2))
        return 0

    if aiohttp is None:
        return reexec_with_uv(forwarded)

    try:
        listings = asyncio.run(run_search(args))
    except FetchError as err:
        print(f'error: {err}', file=sys.stderr)
        return 1

    if args.format == 'json':
        print(format_json(args.city, listings))
    else:
        print(format_table(listings, with_body=args.details))
    return 0


if __name__ == '__main__':
    sys.exit(main())
