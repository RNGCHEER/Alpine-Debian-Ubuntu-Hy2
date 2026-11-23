import base64
import json
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

work = Path(sys.argv[1])
pem = (work / 'trusted.pem').read_text().strip()
links = (work / 'links.txt').read_text(encoding='utf-8').splitlines()
v2 = [line for line in links if line.startswith('v2rayn://')]
hy = [line for line in links if line.startswith('hysteria2://')]
assert len(v2) == len(hy) == 2
password = 'test:"quote"\\slash&?#@'
for index, link in enumerate(v2):
    encoded = link.split('/')[-1]
    item = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
    assert item['ConfigType'] == 7 and item['ConfigVersion'] == 4
    assert item['AllowInsecure'] == 'false'
    assert item['Cert'].replace('\r\n', '\n').strip() == pem
    assert item['Password'] == password
    assert item['Address'] == ['192.0.2.1', '2001:db8::1'][index]
    assert item['Remarks'] == '中文 "节点" & test-IPv' + str([4, 6][index])
for link in hy:
    uri = urlsplit(link)
    assert unquote(uri.username) == password
    assert len(parse_qs(uri.query)['pinSHA256'][0]) == 64
    assert '中文' in unquote(uri.fragment)
sing = json.loads((work / 'sing-box.json').read_text())
xray = json.loads((work / 'xray.json').read_text())
assert sing['tls']['insecure'] is False
assert sing['tls']['certificate'].replace('\r\n', '\n').strip() == pem
assert sing['password'] == password
tls = xray['streamSettings']['tlsSettings']
assert tls['disableSystemRoot'] is True
assert tls['certificates'][0]['usage'] == 'verify'
assert '\n'.join(tls['certificates'][0]['certificate']).strip() == pem
assert xray['settings']['address'] == '2001:db8::1'
assert xray['streamSettings']['hysteriaSettings']['auth'] == password
print('PASS: exports, IPv4/IPv6, UTF-8, JSON/URL escaping, failure cases')
