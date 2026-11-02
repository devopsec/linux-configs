import asyncio
import json
import os
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import aiohttp
import pytest
from aiohttp import web

import find_housing as fh

FIXTURE = Path(__file__).parent / 'fixtures' / 'search_sf.html'
STATIC_FIXTURE = Path(__file__).parent / 'fixtures' / 'search_sf_static.html'
POSTING_FIXTURE = Path(__file__).parent / 'fixtures' / 'posting_sf.html'
EMPTY_PAGE = '<html><body><ul class="cl-static-search-results"></ul></body></html>'
BLOCKED_PAGE = (
    '<html><head><title>blocked</title></head><body>'
    '<h1>This IP has been automatically blocked</h1><p>Please complete the challenge to continue.</p>'
    '</body></html>'
)


NO_BODY_PAGE = '<html><body><p>This posting has been deleted.</p></body></html>'
DETAIL_SEARCH_PAGE = (
    '<html><body><ul class="cl-static-search-results">'
    '<li class="cl-static-search-result"><a href="/post/1"><span class="title">Sunny 2br 1ba</span></a>'
    '<span class="price">$2,850</span></li>'
    '<li class="cl-static-search-result"><a href="/post/2"><span class="title">Studio near park</span></a>'
    '<span class="price">$1,900</span></li>'
    '<li class="cl-static-search-result"><a href="/post/3"><span class="title">Loft 1bd</span></a>'
    '<span class="price">$2,100</span></li>'
    '<li class="cl-static-search-result"><span class="price">$1,000</span></li>'
    '</ul></body></html>'
)


@pytest.fixture(autouse=True)
def isolated_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    home = tmp_path / 'home'
    home.mkdir()
    monkeypatch.setenv('HOME', str(home))
    return home


@pytest.fixture
def sf_html() -> str:
    return FIXTURE.read_text(encoding='utf-8')


@pytest.fixture
def static_html() -> str:
    return STATIC_FIXTURE.read_text(encoding='utf-8')


@pytest.fixture
def serve_html():
    servers = []

    def serve(html: str) -> str:
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                body = html.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
        return f'http://127.0.0.1:{server.server_address[1]}/search/apa'

    yield serve
    for server in servers:
        server.shutdown()
        server.server_close()


@pytest.fixture
def serve_routes():
    servers = []

    def serve(routes: dict[str, tuple]) -> tuple[str, list[str]]:
        hits: list[str] = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                status, html, *rest = routes.get(self.path, (404, 'not found'))
                if rest:
                    time.sleep(rest[0])
                body = html.encode('utf-8')
                try:
                    self.send_response(status)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
        return f'http://127.0.0.1:{server.server_address[1]}', hits

    yield serve
    for server in servers:
        server.shutdown()
        server.server_close()


@pytest.fixture
def fake_search(monkeypatch: pytest.MonkeyPatch, sf_html: str) -> None:
    async def fake_fetch(session, url):
        return sf_html

    monkeypatch.setattr(fh, 'fetch_search_page', fake_fetch)


def _fake_html(monkeypatch: pytest.MonkeyPatch, html: str) -> None:
    async def fake_fetch(session, url):
        return html

    monkeypatch.setattr(fh, 'fetch_search_page', fake_fetch)


def _free_local_url() -> str:
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    return f'http://127.0.0.1:{port}/search/apa'


def _fetch_from_server(handler, timeout: float = 5) -> str:
    async def go() -> str:
        app = web.Application()
        app.router.add_get('/search/apa', handler)
        runner = web.AppRunner(app)
        await runner.setup()
        await web.TCPSite(runner, '127.0.0.1', 0).start()
        port = runner.addresses[0][1]
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
                return await fh.fetch_search_page(session, f'http://127.0.0.1:{port}/search/apa')
        finally:
            await runner.cleanup()

    return asyncio.run(go())


# URL building

def test_build_search_url_with_all_filters():
    url = fh.build_search_url(
        'san francisco',
        max_rent=3000,
        min_bedrooms=1,
        max_bedrooms=2,
        min_bathrooms=1,
        max_bathrooms=2,
        query='dog friendly',
    )
    assert url == (
        'https://sfbay.craigslist.org/search/apa?max_price=3000&min_bedrooms=1&max_bedrooms=2'
        '&min_bathrooms=1&max_bathrooms=2&query=dog+friendly&availabilityMode=0&sale_date=all+dates&sort=date'
    )


def test_build_search_url_without_filters_has_only_defaults():
    url = fh.build_search_url('san francisco')
    assert url == 'https://sfbay.craigslist.org/search/apa?availabilityMode=0&sale_date=all+dates&sort=date'


def test_build_search_url_formats_fractional_bathrooms():
    url = fh.build_search_url('boston', min_bathrooms=1.5)
    assert parse_qs(urlparse(url).query)['min_bathrooms'] == ['1.5']


@pytest.mark.parametrize(
    'filters',
    [{'max_rent': 0}, {'min_bedrooms': 0}, {'max_bedrooms': 0}, {'min_bathrooms': 0}, {'max_bathrooms': 0}],
)
def test_build_search_url_ignores_non_positive_filters(filters):
    url = fh.build_search_url('boston', **filters)
    assert url == 'https://boston.craigslist.org/search/apa?availabilityMode=0&sale_date=all+dates&sort=date'


def test_query_is_url_encoded_and_cannot_inject_parameters():
    url = fh.build_search_url('san francisco', query='cats&max_price=1 pets')
    params = parse_qs(urlparse(url).query)
    assert params['query'] == ['cats&max_price=1 pets']
    assert 'max_price' not in params


@pytest.mark.parametrize(
    ('city', 'subdomain'),
    [
        ('san francisco', 'sfbay'),
        ('San Francisco', 'sfbay'),
        ('  new   york ', 'newyork'),
        ('st. louis', 'stlouis'),
        ('Smallville', 'smallville'),
        ('Big   Town', 'bigtown'),
        ('weird/../city', 'weirdcity'),
    ],
)
def test_city_mapping_and_fallback(city, subdomain):
    assert fh.craigslist_subdomain(city) == subdomain


# Parsing

def test_parse_returns_structured_listings(sf_html):
    listings = fh.parse_search_results(sf_html, limit=5)

    assert len(listings) == 5
    assert listings[0] == fh.Listing(
        title='Sunny 1BR in the Mission, dog friendly',
        url='https://sfbay.craigslist.org/sfc/apa/d/san-francisco-sunny-1br-in-the-mission/7701234567.html',
        rent=2850,
        location='Mission District',
        bedrooms=1,
        bathrooms=None,
        body=None,
    )


def test_parse_extracts_bedrooms_and_fractional_bathrooms(sf_html):
    listings = fh.parse_search_results(sf_html, limit=10)
    by_title = {listing.title: listing for listing in listings}

    bright = by_title['Bright 2 bed/1 bath near Golden Gate Park']
    assert (bright.rent, bright.bedrooms, bright.bathrooms, bright.location) == (3400, 2, 1.0, 'Inner Sunset')

    top_floor = by_title['Top-floor 2BR with views']
    assert (top_floor.bedrooms, top_floor.bathrooms, top_floor.rent) == (2, 1.5, 2600)

    spacious = by_title['Spacious 3br house with yard, 2.5 baths']
    assert (spacious.bedrooms, spacious.bathrooms, spacious.location) == (3, 2.5, 'Daly City')


def test_parse_studio_counts_as_zero_bedrooms(sf_html):
    listings = fh.parse_search_results(sf_html, limit=10)
    studio = next(listing for listing in listings if listing.title == 'Cozy studio, pets ok')
    assert (studio.bedrooms, studio.bathrooms, studio.rent) == (0, None, 1995)


def test_parse_malformed_card_keeps_listing_with_none_fields(sf_html):
    listings = fh.parse_search_results(sf_html, limit=10)
    malformed = next(listing for listing in listings if listing.title.startswith('Malformed card'))
    assert malformed.url is None
    assert malformed.rent is None
    assert malformed.location is None


@pytest.mark.parametrize(('limit', 'expected'), [(3, 3), (50, 8)])
def test_parse_respects_limit_and_returns_all_when_limit_is_larger(sf_html, limit, expected):
    assert len(fh.parse_search_results(sf_html, limit=limit)) == expected


def test_parse_page_without_cards_returns_empty_list():
    assert fh.parse_search_results(EMPTY_PAGE, limit=10) == []


def test_static_markup_parses_every_field(static_html):
    listings = fh.parse_search_results(static_html, limit=10)
    assert len(listings) == 8
    assert listings[0] == fh.Listing(
        title='Modern 2bd/1ba loft in SoMa',
        url='https://sfbay.craigslist.org/sfc/apa/d/san-francisco-modern-2bd-loft/7711000001.html',
        rent=3600,
        location='Hayes Valley',
        bedrooms=2,
        bathrooms=1.0,
        body=None,
    )


def test_static_markup_location_from_multiline_block(static_html):
    listings = fh.parse_search_results(static_html, limit=10)
    bright = next(listing for listing in listings if listing.title.startswith('Bright 2 bed'))
    assert bright.location == 'Inner Sunset'


def test_static_markup_malformed_card_has_none_fields(static_html):
    listings = fh.parse_search_results(static_html, limit=10)
    malformed = next(listing for listing in listings if listing.title.startswith('Malformed card'))
    assert malformed.url is None
    assert malformed.rent is None
    assert malformed.location is None
    assert malformed.bedrooms is None
    assert malformed.bathrooms is None


@pytest.mark.parametrize(
    ('title', 'bedrooms', 'bathrooms'),
    [
        ('Modern 2bd/1ba loft in SoMa', 2, 1.0),
        ('Bright 2 bed/1 bath near Golden Gate Park', 2, 1.0),
        ('Charming 3 bedroom house, 2.5 baths', 3, 2.5),
        ('Top-floor 2BR with views, 1.5 ba', 2, 1.5),
        ('Airy 1 bedroom apt, 1 bath', 1, 1.0),
        ('Cozy studio, pets ok', 0, None),
        ('Sunny unit near BART, shared bath', None, None),
    ],
)
def test_static_markup_title_fallback_parses_bedroom_and_bathroom_variants(static_html, title, bedrooms, bathrooms):
    listings = fh.parse_search_results(static_html, limit=10)
    listing = next(item for item in listings if item.title == title)
    assert (listing.bedrooms, listing.bathrooms) == (bedrooms, bathrooms)


@pytest.mark.parametrize(
    ('title', 'bedrooms', 'bathrooms'),
    [
        ('Sunny 1-bedroom apt', 1, None),
        ('2-bed 2-bath condo', 2, 2.0),
        ('2 bdrm 1 bth', 2, 1.0),
        ('4bdrm', 4, None),
        ('1BR1BA', 1, 1.0),
        ('2bd2ba', 2, 2.0),
    ],
)
def test_title_fallback_parses_hyphenated_and_run_together_tokens(title, bedrooms, bathrooms):
    html = (
        '<ul class="cl-static-search-results"><li class="cl-static-search-result">'
        f'<a href="https://example.com/listing"><div class="title">{title}</div></a>'
        '</li></ul>'
    )
    listing = fh.parse_search_results(html, limit=1)[0]
    assert (listing.bedrooms, listing.bathrooms) == (bedrooms, bathrooms)


def test_title_fallback_does_not_parse_studio_city_location_as_studio():
    html = (
        '<ul class="cl-static-search-results"><li class="cl-static-search-result">'
        '<a href="https://example.com/listing"><div class="title">Nice apartment</div>'
        '<div class="location">Studio City</div></a>'
        '</li></ul>'
    )
    listing = fh.parse_search_results(html, limit=1)[0]
    assert (listing.bedrooms, listing.bathrooms, listing.location) == (None, None, 'Studio City')


# Output formats

def test_format_table_has_header_and_rows(sf_html):
    table = fh.format_table(fh.parse_search_results(sf_html, limit=2))
    lines = table.splitlines()
    assert lines[0].startswith('#')
    assert 'RENT' in lines[0]
    assert '$2,850' in lines[1]
    assert len(lines) == 3


def test_format_table_empty_message():
    assert fh.format_table([]) == 'No listings found.'


def test_format_json_top_level_shape(sf_html):
    listings = fh.parse_search_results(sf_html, limit=2)
    payload = json.loads(fh.format_json('san francisco', listings))
    assert payload['city'] == 'san francisco'
    assert payload['count'] == 2
    assert set(payload['listings'][0]) == {'title', 'url', 'rent', 'location', 'bedrooms', 'bathrooms', 'body'}


# CLI

def test_check_args_prints_namespace_without_network(monkeypatch, capsys):
    async def no_network(args):
        raise AssertionError('network access attempted')

    monkeypatch.setattr(fh, 'run_search', no_network)
    assert fh.main(['--city', 'san francisco', '--max-rent', '3000', '--check-args']) == 0

    namespace = json.loads(capsys.readouterr().out)
    assert namespace['city'] == 'san francisco'
    assert namespace['max_rent'] == 3000
    assert namespace['max_listings'] == 10
    assert namespace['format'] == 'table'
    assert namespace['check_args'] is True


def test_json_output_parses_and_count_matches_listings(fake_search, capsys):
    assert fh.main(['--city', 'san francisco', '--max-listings', '5', '--format', 'json']) == 0

    payload = json.loads(capsys.readouterr().out)
    assert payload['count'] == len(payload['listings']) == 5
    assert payload['listings'][0]['rent'] == 2850


def test_table_output_is_default(fake_search, capsys):
    assert fh.main(['--city', 'san francisco']) == 0

    out = capsys.readouterr().out
    assert 'RENT' in out
    assert '$2,850' in out
    assert not out.lstrip().startswith('{')


def test_max_listings_larger_than_results_returns_all(fake_search, capsys):
    assert fh.main(['--city', 'san francisco', '--max-listings', '50', '--format', 'json']) == 0
    assert json.loads(capsys.readouterr().out)['count'] == 8


def test_zero_results_exits_zero_with_empty_json(monkeypatch, capsys):
    _fake_html(monkeypatch, EMPTY_PAGE)
    assert fh.main(['--city', 'san francisco', '--format', 'json']) == 0
    assert json.loads(capsys.readouterr().out) == {'city': 'san francisco', 'count': 0, 'listings': []}


def test_zero_results_table_message(monkeypatch, capsys):
    _fake_html(monkeypatch, EMPTY_PAGE)
    assert fh.main(['--city', 'san francisco']) == 0
    assert capsys.readouterr().out.strip() == 'No listings found.'


def test_missing_city_exits_2(capsys):
    with pytest.raises(SystemExit) as exc:
        fh.main([])
    assert exc.value.code == 2


@pytest.mark.parametrize(
    'argv',
    [
        ['--city', 'x', '--max-listings', '0'],
        ['--city', 'x', '--min-bedrooms', '3', '--max-bedrooms', '1'],
        ['--city', 'x', '--min-bathrooms', '3', '--max-bathrooms', '1'],
        ['--city', '   ', '--check-args'],
        ['--city', '///', '--check-args'],
        ['--city', 'x', '--format', 'xml'],
        ['--city', 'x', '--max-rent', 'abc'],
    ],
)
def test_invalid_arguments_exit_2(argv):
    with pytest.raises(SystemExit) as exc:
        fh.main(argv)
    assert exc.value.code == 2


def test_connection_refused_exits_1_with_empty_stdout(monkeypatch, capsys):
    url = _free_local_url()
    monkeypatch.setattr(fh, 'build_search_url', lambda *args, **kwargs: url)

    assert fh.main(['--city', 'san francisco']) == 1
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'error:' in captured.err


# Network failure handling

def test_connection_refused_raises_fetch_error():
    async def go():
        async with aiohttp.ClientSession() as session:
            await fh.fetch_search_page(session, _free_local_url())

    with pytest.raises(fh.FetchError):
        asyncio.run(go())


def test_http_500_raises_fetch_error():
    async def server_error(request):
        return web.Response(status=500, text='boom')

    with pytest.raises(fh.FetchError):
        _fetch_from_server(server_error)


def test_empty_response_raises_fetch_error():
    async def empty(request):
        return web.Response(text='   ')

    with pytest.raises(fh.FetchError, match='empty response'):
        _fetch_from_server(empty)


def test_invalid_response_encoding_raises_fetch_error():
    async def invalid_encoding(request):
        return web.Response(body=b'\xff', content_type='text/html', charset='utf-8')

    with pytest.raises(fh.FetchError, match='decode'):
        _fetch_from_server(invalid_encoding)


def test_timeout_raises_fetch_error():
    async def slow(request):
        await asyncio.sleep(1)
        return web.Response(text=EMPTY_PAGE)

    with pytest.raises(fh.FetchError):
        _fetch_from_server(slow, timeout=0.2)


def test_successful_fetch_returns_html(sf_html):
    async def ok(request):
        return web.Response(text=sf_html)

    assert _fetch_from_server(ok) == sf_html


def test_blocked_page_raises_fetch_error():
    async def blocked(request):
        return web.Response(text=BLOCKED_PAGE, content_type='text/html')

    with pytest.raises(fh.FetchError, match='unexpected page markup'):
        _fetch_from_server(blocked)


def test_empty_results_container_is_a_valid_page():
    async def empty(request):
        return web.Response(text=EMPTY_PAGE, content_type='text/html')

    assert fh.parse_search_results(_fetch_from_server(empty), limit=10) == []


def test_blocked_page_cli_exits_1_with_empty_stdout(serve_html, monkeypatch, capsys):
    url = serve_html(BLOCKED_PAGE)
    monkeypatch.setattr(fh, 'build_search_url', lambda *args, **kwargs: url)

    assert fh.main(['--city', 'san francisco', '--format', 'json']) == 1
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'unexpected page markup' in captured.err


def test_empty_results_container_cli_exits_0_with_count_zero(serve_html, monkeypatch, capsys):
    url = serve_html(EMPTY_PAGE)
    monkeypatch.setattr(fh, 'build_search_url', lambda *args, **kwargs: url)

    assert fh.main(['--city', 'san francisco', '--format', 'json']) == 0
    assert json.loads(capsys.readouterr().out)['count'] == 0


# Posting details utilities and validation

SEARCH_URL = 'https://sfbay.craigslist.org/search/apa'


@pytest.mark.parametrize(
    'url',
    [
        'https://sfbay.craigslist.org/sfc/apa/1.html',
        'https://SFBAY.CRAIGSLIST.ORG/sfc/apa/1.html',
        'https://sfbay.craigslist.org:443/sfc/apa/1.html',
        'https://other.craigslist.org/apa/1.html',
        'https://craigslist.org/apa/1.html',
    ],
)
def test_is_valid_detail_url_accepts_craigslist_hosts(url):
    assert fh.is_valid_detail_url(url, SEARCH_URL)


@pytest.mark.parametrize(
    'url',
    [
        'https://evil.com/apa/1.html',
        'https://evilcraigslist.org/apa/1.html',
        'https://sfbay.craigslist.org.evil.com/apa/1.html',
        'http://169.254.169.254/latest/meta-data',
        'http://127.0.0.1:1234/post/1',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'https://sfbay.craigslist.org:8443/apa/1.html',
        'https://sfbay.craigslist.org:99999/apa/1.html',
        'https://user:pw@sfbay.craigslist.org/apa/1.html',
        'https://sfbay.craigslist.org@evil.com/apa/1.html',
        'https://evil.com\\@sfbay.craigslist.org/apa/1.html',
        'https://[::1/apa/1.html',
        '',
    ],
)
def test_is_valid_detail_url_rejects_unsafe_urls(url):
    assert not fh.is_valid_detail_url(url, SEARCH_URL)


def test_is_valid_detail_url_allows_only_search_origin_for_local_server():
    search_url = 'http://127.0.0.1:1234/search/apa'
    assert fh.is_valid_detail_url('http://127.0.0.1:1234/post/1', search_url)
    assert not fh.is_valid_detail_url('http://127.0.0.1:4321/post/1', search_url)
    assert not fh.is_valid_detail_url('http://localhost:1234/post/1', search_url)


@pytest.mark.parametrize(
    ('posting', 'expected'),
    [
        ('Sentence 1. <b>Bold</b> and <i>italic</i>.<br>Line 2.', 'Sentence 1. Bold and italic.\nLine 2.'),
        ('Intro text<p>Para one</p>tail', 'Intro text\nPara one\ntail'),
        ('Rent is\n  <b>$2,850</b>   per\nmonth.', 'Rent is $2,850 per month.'),
    ],
)
def test_fetch_posting_body_formats_inline_and_block_text(serve_routes, posting, expected):
    base, _ = serve_routes({'/post/1': (200, f'<section id="postingbody">{posting}</section>')})
    assert _fetch_body(base, '/post/1') == expected


# Posting details

def _fetch_body(base_url: str, path: str, timeout: float = 5) -> str | None:
    async def go():
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
            return await fh.fetch_posting_body(session, base_url + path)

    return asyncio.run(go())


def _run_details(monkeypatch, serve_routes, routes, argv, search_html=DETAIL_SEARCH_PAGE):
    base, hits = serve_routes({'/search/apa': (200, search_html), **routes})
    monkeypatch.setattr(fh, 'build_search_url', lambda *args, **kwargs: f'{base}/search/apa')
    return fh.main(['--city', 'san francisco', *argv]), hits


def _post_hits(hits: list[str]) -> list[str]:
    return sorted(hit for hit in hits if hit.startswith('/post/'))


def _search_page(hrefs: list[str]) -> str:
    cards = ''.join(
        f'<li class="cl-static-search-result"><a href="{href}"><span class="title">Listing {index}</span></a>'
        f'<span class="price">${1000 + index}</span></li>'
        for index, href in enumerate(hrefs, start=1)
    )
    return f'<html><body><ul class="cl-static-search-results">{cards}</ul></body></html>'


def _record_gets(monkeypatch) -> list[str]:
    requested: list[str] = []
    original = fh._get_text

    async def recording(session, url):
        requested.append(url)
        return await original(session, url)

    monkeypatch.setattr(fh, '_get_text', recording)
    return requested


def test_fetch_posting_body_returns_clean_text(serve_routes):
    base, _ = serve_routes({'/post/1': (200, POSTING_FIXTURE.read_text(encoding='utf-8'))})
    assert _fetch_body(base, '/post/1') == (
        'Bright top-floor unit with hardwood floors and a renovated kitchen.\n'
        'Laundry in building. Dog friendly, cats welcome with deposit.\n'
        'Available November 1. Street parking only.'
    )


def test_fetch_posting_body_missing_element_is_none(serve_routes):
    base, _ = serve_routes({'/post/1': (200, NO_BODY_PAGE)})
    assert _fetch_body(base, '/post/1') is None


def test_fetch_posting_body_empty_element_is_none(serve_routes):
    base, _ = serve_routes({'/post/1': (200, '<section id="postingbody">   </section>')})
    assert _fetch_body(base, '/post/1') is None


def test_fetch_posting_body_http_error_raises_fetch_error(serve_routes):
    base, _ = serve_routes({'/post/1': (500, 'boom')})
    with pytest.raises(fh.FetchError, match='failed'):
        _fetch_body(base, '/post/1')


def test_fetch_posting_body_timeout_raises_fetch_error(serve_routes):
    base, _ = serve_routes({'/post/1': (200, POSTING_FIXTURE.read_text(encoding='utf-8'), 1)})
    with pytest.raises(fh.FetchError):
        _fetch_body(base, '/post/1', timeout=0.2)


def test_details_json_adds_body_per_listing(monkeypatch, serve_routes, capsys):
    posting = POSTING_FIXTURE.read_text(encoding='utf-8')
    code, hits = _run_details(
        monkeypatch,
        serve_routes,
        {'/post/1': (200, posting), '/post/2': (200, NO_BODY_PAGE), '/post/3': (200, posting)},
        ['--details', '--format', 'json'],
    )

    assert code == 0
    listings = json.loads(capsys.readouterr().out)['listings']
    assert len(listings) == 4
    assert listings[0]['body'].startswith('Bright top-floor unit')
    assert listings[1]['body'] is None
    assert listings[2]['body'].startswith('Bright top-floor unit')
    assert listings[3]['body'] is None
    assert _post_hits(hits) == ['/post/1', '/post/2', '/post/3']


def test_details_max_listings_caps_detail_requests(monkeypatch, serve_routes, capsys):
    posting = POSTING_FIXTURE.read_text(encoding='utf-8')
    code, hits = _run_details(
        monkeypatch,
        serve_routes,
        {'/post/1': (200, posting), '/post/2': (200, posting), '/post/3': (200, posting)},
        ['--details', '--max-listings', '2', '--format', 'json'],
    )

    assert code == 0
    assert json.loads(capsys.readouterr().out)['count'] == 2
    assert _post_hits(hits) == ['/post/1', '/post/2']


def test_without_details_flag_no_posting_requests(monkeypatch, serve_routes, capsys):
    code, hits = _run_details(
        monkeypatch,
        serve_routes,
        {'/post/1': (200, POSTING_FIXTURE.read_text(encoding='utf-8'))},
        ['--format', 'json'],
    )

    assert code == 0
    assert _post_hits(hits) == []
    assert all(listing['body'] is None for listing in json.loads(capsys.readouterr().out)['listings'])


def test_details_table_prints_bodies_below_table(monkeypatch, serve_routes, capsys):
    code, _ = _run_details(
        monkeypatch,
        serve_routes,
        {
            '/post/1': (200, POSTING_FIXTURE.read_text(encoding='utf-8')),
            '/post/2': (200, NO_BODY_PAGE),
            '/post/3': (200, POSTING_FIXTURE.read_text(encoding='utf-8')),
        },
        ['--details'],
    )

    out = capsys.readouterr().out
    assert code == 0
    assert out.startswith('#')
    assert '[1] Sunny 2br 1ba' in out
    assert 'Dog friendly, cats welcome with deposit.' in out
    assert '[2] Studio near park\n(no posting body found)' in out


def test_details_http_error_exits_1_with_empty_stdout(monkeypatch, serve_routes, capsys):
    code, _ = _run_details(
        monkeypatch,
        serve_routes,
        {'/post/1': (200, POSTING_FIXTURE.read_text(encoding='utf-8')), '/post/2': (500, 'boom')},
        ['--details', '--format', 'json'],
    )

    captured = capsys.readouterr()
    assert code == 1
    assert captured.out == ''
    assert 'error:' in captured.err


def test_details_timeout_exits_1_with_empty_stdout(monkeypatch, serve_routes, capsys):
    monkeypatch.setattr(fh, 'REQUEST_TIMEOUT_SECONDS', 0.2)
    posting = POSTING_FIXTURE.read_text(encoding='utf-8')
    code, _ = _run_details(
        monkeypatch,
        serve_routes,
        {f'/post/{index}': (200, posting, 1) for index in range(1, 4)},
        ['--details', '--format', 'json'],
    )

    captured = capsys.readouterr()
    assert code == 1
    assert captured.out == ''
    assert 'error:' in captured.err
    assert 'TimeoutError' in captured.err


def test_details_concurrency_is_bounded(monkeypatch, fake_search, capsys):
    in_flight = 0
    peak = 0

    async def fake_body(session, url):
        nonlocal in_flight, peak
        in_flight += 1
        peak = max(peak, in_flight)
        await asyncio.sleep(0.01)
        in_flight -= 1
        return 'body'

    monkeypatch.setattr(fh, 'fetch_posting_body', fake_body)

    assert fh.main(['--city', 'san francisco', '--details', '--format', 'json']) == 0
    listings = json.loads(capsys.readouterr().out)['listings']
    assert peak == fh.DETAIL_CONCURRENCY
    assert {listing['body'] for listing in listings} <= {'body', None}
    assert any(listing['body'] == 'body' for listing in listings)


def test_details_skips_off_domain_hrefs_without_any_request(monkeypatch, serve_routes, capsys):
    posting = POSTING_FIXTURE.read_text(encoding='utf-8')
    search_html = _search_page(
        [
            '/post/1',
            'https://evil.example/p',
            '//evil.example/p',
            'http://169.254.169.254/latest/meta-data',
            'https://evil.example\\@sfbay.craigslist.org/p',
        ]
    )
    base, hits = serve_routes({'/search/apa': (200, search_html), '/post/1': (200, posting)})
    monkeypatch.setattr(fh, 'build_search_url', lambda *args, **kwargs: f'{base}/search/apa')
    requested = _record_gets(monkeypatch)

    assert fh.main(['--city', 'san francisco', '--details', '--format', 'json']) == 0

    captured = capsys.readouterr()
    listings = json.loads(captured.out)['listings']
    assert [listing['body'] is not None for listing in listings] == [True, False, False, False, False]
    assert _post_hits(hits) == ['/post/1']
    assert requested == [f'{base}/search/apa', f'{base}/post/1']
    assert captured.err.count('skipping invalid detail URL') == 4


def test_details_queued_postings_are_not_requested_after_first_failure(monkeypatch, serve_routes, capsys):
    posting = POSTING_FIXTURE.read_text(encoding='utf-8')
    search_html = _search_page([f'/post/{index}' for index in range(1, 8)])
    routes = {'/post/1': (500, 'boom'), **{f'/post/{index}': (200, posting, 1) for index in range(2, 8)}}
    code, hits = _run_details(monkeypatch, serve_routes, routes, ['--details', '--format', 'json'], search_html)

    captured = capsys.readouterr()
    assert code == 1
    assert captured.out == ''
    assert 'error:' in captured.err
    assert set(_post_hits(hits)) <= {'/post/1', '/post/2', '/post/3', '/post/4'}
    assert '/post/1' in hits


def test_details_unexpected_error_exits_1_without_traceback(monkeypatch, fake_search, capsys):
    async def broken_body(session, url):
        raise RuntimeError('parser exploded')

    monkeypatch.setattr(fh, 'fetch_posting_body', broken_body)

    assert fh.main(['--city', 'san francisco', '--details', '--format', 'json']) == 1
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'unexpected error while fetching postings' in captured.err
    assert 'Traceback' not in captured.err


# Bootstrap: deps-free entry points and uv re-exec

SCRIPT = Path(fh.__file__).resolve()


def _run_without_deps(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, '-I', '-S', str(SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_check_args_works_without_third_party_deps():
    result = _run_without_deps('--city', 'san francisco', '--max-rent', '3000', '--check-args')
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['max_rent'] == 3000


def test_no_args_without_third_party_deps_exits_2_with_usage():
    result = _run_without_deps()
    assert result.returncode == 2
    assert result.stdout == ''
    assert 'usage:' in result.stderr
    assert '--city' in result.stderr


@pytest.fixture
def no_deps(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(fh, 'aiohttp', None)
    monkeypatch.delenv(fh.UV_REEXEC_ENV, raising=False)


class _Completed:
    def __init__(self, returncode: int):
        self.returncode = returncode


def test_reexec_runs_script_under_uv_with_forwarded_argv(monkeypatch, no_deps):
    calls = []

    def fake_run(cmd, **kwargs):
        calls.append((cmd, kwargs))
        return _Completed(0)

    monkeypatch.setattr(fh.subprocess, 'run', fake_run)

    argv = ['--city', 'austin', '--format', 'json']
    assert fh.main(argv) == 0

    cmd, kwargs = calls[0]
    assert cmd == ['uv', 'run', '--quiet', str(SCRIPT), *argv]
    assert kwargs['env'][fh.UV_REEXEC_ENV] == '1'


@pytest.mark.parametrize(('child_code', 'expected'), [(0, 0), (1, 1), (2, 1), (-9, 1)])
def test_reexec_maps_child_exit_codes(monkeypatch, no_deps, capsys, child_code, expected):
    monkeypatch.setattr(fh.subprocess, 'run', lambda cmd, **kwargs: _Completed(child_code))

    assert fh.reexec_with_uv(['--city', 'austin']) == expected
    captured = capsys.readouterr()
    assert captured.out == ''
    if child_code == 2:
        assert 'could not resolve aiohttp and beautifulsoup4 via uv run' in captured.err


def test_reexec_missing_uv_binary_exits_1(monkeypatch, no_deps, capsys):
    def missing_uv(cmd, **kwargs):
        raise FileNotFoundError(2, 'No such file or directory', 'uv')

    monkeypatch.setattr(fh.subprocess, 'run', missing_uv)

    assert fh.main(['--city', 'austin']) == 1
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'uv could not start' in captured.err


def test_reexec_guard_prevents_loop(monkeypatch, no_deps, capsys):
    def must_not_run(cmd, **kwargs):
        raise AssertionError('uv must not be re-invoked when the guard is set')

    monkeypatch.setattr(fh.subprocess, 'run', must_not_run)
    monkeypatch.setenv(fh.UV_REEXEC_ENV, '1')

    assert fh.main(['--city', 'austin']) == 1
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'unavailable even under uv run' in captured.err


def test_check_args_does_not_reexec(monkeypatch, no_deps, capsys):
    def must_not_run(cmd, **kwargs):
        raise AssertionError('--check-args must not invoke uv')

    monkeypatch.setattr(fh.subprocess, 'run', must_not_run)

    assert fh.main(['--city', 'austin', '--check-args']) == 0
    assert json.loads(capsys.readouterr().out)['city'] == 'austin'


def test_main_without_argv_forwards_sys_argv(monkeypatch, no_deps):
    calls = []
    monkeypatch.setattr(fh.subprocess, 'run', lambda cmd, **kwargs: calls.append(cmd) or _Completed(0))
    monkeypatch.setattr(sys, 'argv', ['find_housing.py', '--city', 'boston', '--format', 'json'])

    assert fh.main() == 0
    assert calls[0][-4:] == ['--city', 'boston', '--format', 'json']


# Config file: ~/.config/find_housing.cfg

CONFIG_SAMPLE = (
    '[find_housing]\n'
    'city = san francisco\n'
    'max_rent = 3000\n'
    'min_bedrooms = 1\n'
    'max_bedrooms = 3\n'
    'min_bathrooms = 1\n'
    'max_bathrooms = 2.5\n'
    'query = dog friendly\n'
    'max_listings = 4\n'
    'details = no\n'
    'format = json\n'
)


def _write_config(home: Path, text: str) -> Path:
    path = home / '.config' / 'find_housing.cfg'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')
    return path


def _check_args(capsys, *argv: str) -> dict:
    assert fh.main([*argv, '--check-args']) == 0
    return json.loads(capsys.readouterr().out)


def _run_malformed(capsys, *argv: str) -> str:
    with pytest.raises(SystemExit) as exc:
        fh.main(list(argv))
    assert exc.value.code == 2
    captured = capsys.readouterr()
    assert captured.out == ''
    assert 'Traceback' not in captured.err
    return captured.err


def test_config_path_is_under_home(isolated_home):
    assert fh.config_path() == str(isolated_home / '.config' / 'find_housing.cfg')


def test_missing_config_keeps_builtin_defaults(capsys):
    namespace = _check_args(capsys, '--city', 'austin')
    assert namespace['max_listings'] == 10
    assert namespace['format'] == 'table'
    assert namespace['details'] is False
    assert namespace['max_rent'] is None
    assert namespace['query'] is None


def test_config_file_supplies_every_option(isolated_home, capsys):
    _write_config(isolated_home, CONFIG_SAMPLE)
    namespace = _check_args(capsys)
    expected = {
        'city': 'san francisco',
        'max_rent': 3000,
        'min_bedrooms': 1,
        'max_bedrooms': 3,
        'min_bathrooms': 1.0,
        'max_bathrooms': 2.5,
        'query': 'dog friendly',
        'max_listings': 4,
        'details': False,
        'format': 'json',
    }
    assert {key: namespace[key] for key in expected} == expected


def test_cli_options_override_config(isolated_home, capsys):
    _write_config(isolated_home, CONFIG_SAMPLE)
    namespace = _check_args(
        capsys, '--city', 'austin', '--max-rent', '2000', '--details', '--format', 'table',
        '--max-listings', '7', '--query', 'quiet street',
    )
    assert namespace['city'] == 'austin'
    assert namespace['max_rent'] == 2000
    assert namespace['details'] is True
    assert namespace['format'] == 'table'
    assert namespace['max_listings'] == 7
    assert namespace['query'] == 'quiet street'
    assert namespace['min_bedrooms'] == 1


def test_no_details_overrides_config_details_true(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\ndetails = yes\n')
    assert _check_args(capsys)['details'] is True
    assert _check_args(capsys, '--no-details')['details'] is False


def test_config_provides_city_when_cli_omits_it(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = boston\n')
    assert _check_args(capsys)['city'] == 'boston'


def test_bare_command_without_city_anywhere_exits_2(capsys):
    with pytest.raises(SystemExit) as exc:
        fh.main([])
    assert exc.value.code == 2
    assert '--city is required' in capsys.readouterr().err


def test_config_without_city_and_no_cli_city_exits_2(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\nmax_rent = 2000\n')
    err = _run_malformed(capsys, '--check-args')
    assert '--city is required' in err


def test_config_query_empty_means_no_query(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\nquery =\n')
    assert _check_args(capsys)['query'] is None


@pytest.mark.parametrize('line', ['city = "san francisco"', "city = 'san francisco'", 'city = san francisco # home',
                                  'city = "san francisco" ; home'])
def test_config_city_quotes_and_inline_comments(isolated_home, capsys, line):
    _write_config(isolated_home, f'[find_housing]\n{line}\n')
    city = _check_args(capsys)['city']
    assert city == 'san francisco'
    assert fh.craigslist_subdomain(city) == 'sfbay'


def test_config_query_and_format_quotes_and_punctuation(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\nquery = "dog friendly"  # pets\nformat = "json"\n')
    namespace = _check_args(capsys)
    assert namespace['query'] == 'dog friendly'
    assert namespace['format'] == 'json'
    _write_config(isolated_home, '[find_housing]\ncity = austin\nquery = dog & cat\n')
    assert _check_args(capsys)['query'] == 'dog & cat'


def test_config_unmatched_quote_is_kept_literal(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\nquery = "dog\n')
    assert _check_args(capsys)['query'] == '"dog'


@pytest.mark.parametrize(
    ('cfg', 'cli', 'expected'),
    [
        ('min_bedrooms = 3', ['--max-bedrooms', '2'], ('min_bedrooms = 3', '--max-bedrooms 2')),
        ('max_bedrooms = 1', ['--min-bedrooms', '2'], ('max_bedrooms = 1', '--min-bedrooms 2')),
        ('min_bathrooms = 2.5', ['--max-bathrooms', '1'], ('min_bathrooms = 2.5', '--max-bathrooms 1.0')),
        ('min_bedrooms = 1\nmax_bedrooms = 3', ['--max-bedrooms', '0'], ('min_bedrooms = 1', '--max-bedrooms 0')),
    ],
)
def test_cross_source_range_conflict_names_config_and_cli(isolated_home, capsys, cfg, cli, expected):
    path = _write_config(isolated_home, f'[find_housing]\ncity = austin\n{cfg}\n')
    err = _run_malformed(capsys, *cli)
    assert str(path) in err
    assert all(part in err for part in expected)
    assert 'must not exceed --' not in err


def test_cross_source_same_key_cli_wins_without_conflict(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\nmin_bedrooms = 3\nmax_bedrooms = 4\n')
    namespace = _check_args(capsys, '--min-bedrooms', '1', '--max-bedrooms', '2')
    assert (namespace['min_bedrooms'], namespace['max_bedrooms']) == (1, 2)


def test_config_values_are_not_interpolated(isolated_home, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = austin\nquery = 100%% dog\n')
    assert _check_args(capsys)['query'] == '100%% dog'


@pytest.mark.parametrize(
    ('text', 'message'),
    [
        ('[find_housing\ncity = austin\n', 'invalid config file'),
        ('city = austin\n', 'invalid config file'),
        ('[find_housing]\ncity = austin\ncity = boston\n', 'invalid config file'),
        ('[DEFAULT]\ncity = austin\n[find_housing]\n', 'keys must be inside [find_housing]'),
        ('[find_housing]\ncity = austin\nmax_rents = 3\n', "unknown key 'max_rents'"),
        ('[other]\ncity = austin\n', 'unknown section [other]'),
        ('[find_housing]\ncity = austin\nmax_rent = lots\n', 'max_rent must be a number'),
        ('[find_housing]\ncity = austin\nmax_rent = -5\n', 'max_rent must be a non-negative number'),
        ('[find_housing]\ncity = austin\nmax_bathrooms = nan\n', 'max_bathrooms must be a non-negative number'),
        ('[find_housing]\ncity = austin\nmax_listings = 0\n', 'max_listings must be at least 1'),
        ('[find_housing]\ncity = austin\nmin_bedrooms = 3\nmax_bedrooms = 1\n', 'min_bedrooms must not exceed max_bedrooms'),
        ('[find_housing]\ncity = austin\ndetails = maybe\n', 'details must be yes/no'),
        ('[find_housing]\ncity = austin\nformat = xml\n', 'format must be one of table, json'),
        ('[find_housing]\ncity =   \n', 'city must not be empty'),
        ('[find_housing]\ncity = ///\n', 'city must contain at least one letter or digit'),
    ],
)
def test_malformed_config_exits_2_without_traceback(isolated_home, capsys, text, message):
    path = _write_config(isolated_home, text)
    err = _run_malformed(capsys, '--check-args')
    assert message in err
    assert str(path) in err
    assert err.count('error:') == 1


def test_config_path_that_is_a_directory_exits_2(isolated_home, capsys):
    (isolated_home / '.config' / 'find_housing.cfg').mkdir(parents=True)
    err = _run_malformed(capsys, '--city', 'austin', '--check-args')
    assert 'cannot read config' in err


def test_config_check_args_makes_no_network_call(isolated_home, monkeypatch, capsys):
    _write_config(isolated_home, CONFIG_SAMPLE)

    async def no_network(args):
        raise AssertionError('network access attempted')

    monkeypatch.setattr(fh, 'run_search', no_network)
    assert _check_args(capsys)['city'] == 'san francisco'


def test_config_options_apply_to_search_run(isolated_home, fake_search, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = san francisco\nmax_listings = 3\nformat = json\n')
    assert fh.main([]) == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload['city'] == 'san francisco'
    assert payload['count'] == len(payload['listings']) == 3


def test_cli_format_json_overrides_config_table(isolated_home, fake_search, capsys):
    _write_config(isolated_home, '[find_housing]\ncity = san francisco\nformat = table\n')
    assert fh.main(['--format', 'json']) == 0
    assert json.loads(capsys.readouterr().out)['count'] > 0


def test_config_check_args_works_without_third_party_deps(isolated_home):
    _write_config(isolated_home, '[find_housing]\ncity = boston\nmax_rent = 2500\n')
    result = _run_without_deps('--check-args')
    assert result.returncode == 0, result.stderr
    namespace = json.loads(result.stdout)
    assert namespace['city'] == 'boston'
    assert namespace['max_rent'] == 2500


def test_malformed_config_without_deps_exits_2(isolated_home):
    _write_config(isolated_home, '[find_housing]\nmax_rent = lots\n')
    result = _run_without_deps('--city', 'austin', '--check-args')
    assert result.returncode == 2
    assert result.stdout == ''
    assert 'max_rent must be a number' in result.stderr
    assert 'Traceback' not in result.stderr
