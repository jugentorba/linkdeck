#!/usr/bin/env python3
"""Build shared/blocklist.txt from public ad/tracker host lists.

Sources:
  - AdAway default mobile ad blocklist (GPLv3)
  - A curated list of ad networks / popup networks

Output: one domain per line, sorted, comments allowed with '#'.
Matching convention in the apps: a request host is blocked when it equals
an entry or ends with "." + entry (suffix match).
"""
import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "shared", "blocklist.txt")

EXTRA = """
# --- ad exchanges / SSPs / trackers -----------------------------------------
doubleclick.net
googleadservices.com
googlesyndication.com
google-analytics.com
googletagmanager.com
googletagservices.com
adservice.google.com
2mdn.net
adnxs.com
adsrvr.org
adcolony.com
applovin.com
chartboost.com
unityads.unity3d.com
vungle.com
ironsrc.com
supersonicads.com
inmobi.com
mopub.com
startapp.com
tapjoy.com
adform.net
adroll.com
adsafeprotected.com
advertising.com
amazon-adsystem.com
appnexus.com
bidswitch.net
casalemedia.com
contextweb.com
criteo.com
criteo.net
demdex.net
dotomi.com
exelator.com
eyeota.net
gumgum.com
indexww.com
inmobi.com
krxd.net
lijit.com
mathtag.com
media.net
moatads.com
mookie1.com
openx.net
outbrain.com
pubmatic.com
quantcast.com
quantserve.com
rubiconproject.com
rfihub.com
scorecardresearch.com
sharethrough.com
simpli.fi
smartadserver.com
sovrn.com
spotxchange.com
taboola.com
teads.tv
tremorhub.com
triplelift.com
turn.com
yieldmo.com
zemanta.com
zergnet.com
# --- classic popup / redirect networks --------------------------------------
popads.net
popcash.net
propellerads.com
propellerpops.com
onclickads.net
clickadu.com
exoclick.com
exosrv.com
juicyads.com
trafficjunky.com
trafficfactory.biz
adsterra.com
hilltopads.net
adcash.com
clickaine.com
adspyglass.com
a-ads.com
cointraffic.io
coinzilla.io
coinhive.com
crypto-loot.com
webminepool.com
minexmr.com
# --- malvertising / scam redirectors ----------------------------------------
admaven.com
ad-maven.com
clksite.com
trkclk.com
tsyndicate.com
trafficstars.com
revenuehits.com
revcontent.com
mgid.com
newsmaxfeednetwork.com
adskeeper.com
""".splitlines()

# lines that must never be blocked (kept out even if upstream lists them)
ALLOW = {
    "mediavine.com",
    "akamaized.net",
    "akamaihd.net",
    "cloudfront.net",
    "googlevideo.com",
    "ytimg.com",
    "ggpht.com",
    "fbcdn.net",
    "twimg.com",
}

HOST_RE = re.compile(r"^[a-z0-9]([a-z0-9._-]*[a-z0-9])?\.[a-z]{2,}$")


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "ignore")


def parse_hosts(text: str) -> set[str]:
    out = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        host = parts[-1] if parts[0] in ("0.0.0.0", "127.0.0.1", "::1") else parts[0]
        host = host.lower().strip(".")
        if HOST_RE.fullmatch(host):
            out.add(host)
    return out


def main() -> None:
    domains: set[str] = set()

    adaway_url = "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"
    try:
        domains |= parse_hosts(fetch(adaway_url))
    except Exception as exc:  # noqa: BLE001
        print(f"warning: could not fetch AdAway list: {exc}")

    for raw in EXTRA:
        raw = raw.strip()
        if not raw or raw.startswith("#") or " " in raw:
            continue
        if HOST_RE.fullmatch(raw):
            domains.add(raw)

    for host in ALLOW:
        domains.discard(host)
        domains = {d for d in domains if not d.endswith("." + host)}

    domains = sorted(domains)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("# LinkDeck ad & tracker blocklist\n")
        fh.write("# Sources: AdAway default list (GPLv3), curated ad-network additions.\n")
        fh.write("# Suffix matching: entry 'example.com' blocks example.com and *.example.com\n")
        fh.write(f"# Entries: {len(domains)}\n")
        fh.write("\n".join(domains))
        fh.write("\n")
    print(f"wrote {OUT}: {len(domains)} domains")


if __name__ == "__main__":
    main()
