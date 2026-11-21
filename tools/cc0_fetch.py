"""Fetches CC0 / public-domain sounds and music for Cutline.

Sources (both free to use, change and ship, no credit required):
  - Kenney.nl audio packs (CC0 1.0)
  - FreePD.com music (public domain / CC0)

Output:
  cc0/kenney/<pack>/*.ogg      raw sounds, for picking and processing later
  cc0/inventory.json           every sound with its length
  music/<id>.m4a + music.json  the music library, grouped by mood
  cc0/proof/                   the source pages, as a record of the licence
"""
import json, os, re, subprocess, sys, urllib.request, urllib.parse, zipfile, io, hashlib, http.cookiejar

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"}
JAR = http.cookiejar.CookieJar()
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(JAR))
KENNEY = ["interface-sounds", "impact-sounds", "digital-audio", "ui-audio", "casino-audio",
          "music-jingles", "sci-fi-sounds", "rpg-audio"]
MOODS = {  # FreePD page -> mood shown in the app
    "upbeat": "Happy", "electronic": "Energetic", "epic": "Epic", "romantic": "Calm",
    "comedy": "Funny", "scoring": "Cinematic", "world": "World", "misc": "Chill",
}
PER_MOOD = 6
MAX_SECONDS = 150


def get(url, referer=None):
    req = urllib.request.Request(url, headers=dict(UA, Referer=referer or url))
    with OPENER.open(req, timeout=120) as r:
        return r.read()


def seconds(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", path], capture_output=True, text=True).stdout
    try:
        return round(float(out.strip()), 3)
    except ValueError:
        return 0.0


def kenney():
    os.makedirs("cc0/proof", exist_ok=True)
    inventory = []
    for slug in KENNEY:
        try:
            page = get(f"https://kenney.nl/assets/{slug}").decode("utf-8", "ignore")
        except Exception as e:
            print("kenney page failed", slug, e); continue
        open(f"cc0/proof/kenney-{slug}.html", "w").write(page)
        ids = re.findall(r"data-download-id='([0-9a-f]+)'", page)
        if not ids:
            print("no download on", slug); continue
        try:
            link = json.loads(get("https://kenney.nl/download-link/" + ids[0], f"https://kenney.nl/assets/{slug}"))["url"]
            print("kenney", slug, link)
            data = get(link, f"https://kenney.nl/assets/{slug}")
        except Exception as e:
            print("zip failed", slug, e); continue
        z = zipfile.ZipFile(io.BytesIO(data))
        for name in z.namelist():
            low = name.lower()
            if low.endswith("license.txt") or low.endswith("license.md"):
                open(f"cc0/proof/kenney-{slug}-license.txt", "wb").write(z.read(name))
            if not low.endswith((".ogg", ".wav", ".mp3")):
                continue
            out = f"cc0/kenney/{slug}/" + os.path.basename(name).replace(" ", "_")
            os.makedirs(os.path.dirname(out), exist_ok=True)
            open(out, "wb").write(z.read(name))
            inventory.append({"pack": slug, "file": out, "seconds": seconds(out)})
    json.dump(inventory, open("cc0/inventory.json", "w"), indent=1)
    print("kenney sounds:", len(inventory))


def freepd():
    os.makedirs("music", exist_ok=True)
    catalog = []
    home = get("https://freepd.com/").decode("utf-8", "ignore")
    open("cc0/proof/freepd-home.html", "w").write(home)
    pages = {}
    for href in re.findall(r'href=["\']([^"\']+)["\']', home):
        full = urllib.parse.urljoin("https://freepd.com/", href)
        if full.startswith("https://freepd.com/") and not full.endswith((".mp3", ".css", ".js", ".png", ".jpg")):
            pages.setdefault(full, None)
    print("freepd pages:", list(pages))
    for url in pages:
        slug = url.rstrip("/").rsplit("/", 1)[-1].split(".")[0].lower()
        mood = next((m for k, m in MOODS.items() if k in slug), None)
        if mood is None:
            continue
        try:
            page = get(url).decode("utf-8", "ignore")
        except Exception as e:
            print("freepd page failed", url, e); continue
        open(f"cc0/proof/freepd-{slug}.html", "w").write(page)
        links = []
        for href in re.findall(r'["\']([^"\']+?\.mp3)["\']', page):
            full = urllib.parse.urljoin(url, href)
            if full not in links:
                links.append(full)
        print("freepd", slug, mood, len(links), "tracks")
        taken = 0
        for link in links:
            if taken >= PER_MOOD:
                break
            title = urllib.parse.unquote(link.rsplit("/", 1)[-1])[:-4]
            ident = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
            if any(c["id"] == ident for c in catalog):
                continue
            try:
                raw = get(urllib.parse.quote(link, safe=":/"))
            except Exception as e:
                print("track failed", link, e); continue
            src = f"/tmp/{ident}.mp3"
            open(src, "wb").write(raw)
            length = seconds(src)
            if length < 20:
                continue
            keep = min(length, MAX_SECONDS)
            out = f"music/{ident}.m4a"
            fade_at = max(0.0, keep - 4)
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-t", str(keep),
                            "-af", f"loudnorm=I=-18:TP=-2:LRA=11,afade=t=in:d=0.5,afade=t=out:st={fade_at}:d=4",
                            "-c:a", "aac", "-b:a", "96k", "-ar", "44100", out], check=True)
            body = open(out, "rb").read()
            catalog.append({"id": ident, "title": title, "mood": mood, "seconds": round(keep, 1),
                            "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest(),
                            "source": link, "licence": "Public domain (FreePD.com)"})
            taken += 1
    json.dump({"version": 1, "tracks": catalog}, open("music/music.json", "w"), indent=1, ensure_ascii=False)
    print("music tracks:", len(catalog), "bytes:", sum(c["bytes"] for c in catalog))


if __name__ == "__main__":
    which = sys.argv[1:] or ["kenney", "freepd"]
    if "kenney" in which:
        kenney()
    if "freepd" in which:
        freepd()
