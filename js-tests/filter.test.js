const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");
const { classifyPath, enginePath, hidden, hideCSS, mount, read, selectorConfig } = require("./helpers");

const feedHTML = fs.readFileSync(path.join(__dirname, "fixtures/feed.html"), "utf8");
const reelsHTML = fs.readFileSync(path.join(__dirname, "fixtures/reels.html"), "utf8");

test("hides reels, sends the explore tab to search, and leaves search, messages, and profile", () => {
  const { document } = mount(feedHTML);
  assert.equal(hidden(document.querySelector("a[href='/reels/']")), true);
  const explore = document.querySelector("a[data-enough-href='/explore/']");
  assert.equal(hidden(explore), false);
  assert.equal(explore.getAttribute("href"), "/explore/search/");
  assert.equal(explore.getAttribute("data-enough-search"), "1");
  assert.equal(hidden(document.querySelector("a[href='/explore/search/']:not([data-enough-search])")), false);
  assert.equal(hidden(document.querySelector("a[href='/direct/inbox/']")), false);
  assert.equal(hidden(document.querySelector("a[href='/ada.lovelace/']")), false);
});

test("hides suggested posts and reel posts without hiding ads", () => {
  const { document } = mount(feedHTML);
  assert.equal(hidden(document.querySelector("#organic")), false);
  assert.equal(hidden(document.querySelector("#suggested")), true);
  assert.equal(hidden(document.querySelector("#reel")), false);
  assert.equal(hidden(document.querySelector("#ad")), false);
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
  assert.equal(hidden(document.querySelector("#ad-text")), false);
  assert.equal(document.querySelector("#ad-text").classList.contains("enough-keep"), true);
});

test("does not observe ads, suggested posts, reels, or permalink-less articles", () => {
  const { document, io } = mount(feedHTML);
  const ids = io.elements.map((element) => element.id);
  assert.deepEqual(ids, ["organic", "reel"]);
  assert.equal(document.querySelector("#ad").getAttribute("data-enough-observed"), null);
  assert.equal(document.querySelector("#reel").getAttribute("data-enough-observed"), "1");
  assert.equal(document.querySelector("#nolink").getAttribute("data-enough-observed"), null);
  assert.equal(document.querySelector("#organic").getAttribute("data-enough-key"), "p/POST1");
});

test("turning the toggles off brings hidden posts back and still keeps ads marked", () => {
  const { document, engine } = mount(feedHTML);
  engine.applyToggles({ hideReels: false, hideExplore: false, hideSuggested: false });
  assert.equal(hidden(document.querySelector("a[href='/reels/']")), false);
  assert.equal(hidden(document.querySelector("a[href='/explore/']")), false);
  assert.equal(document.querySelector("a[href='/explore/']").getAttribute("data-enough-search"), null);
  assert.equal(hidden(document.querySelector("#reel")), false);
  assert.equal(hidden(document.querySelector("#suggested")), false);
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
  assert.equal(hidden(document.querySelector("#ad")), false);
});

test("a reels route hides ordinary articles and leaves the sponsored one", () => {
  const { document } = mount(reelsHTML, "https://www.instagram.com/reels/");
  assert.equal(document.documentElement.getAttribute("data-enough-route"), "reels");
  assert.equal(hidden(document.querySelector("#reel-card")), true);
  assert.equal(hidden(document.querySelector("#ad")), false);
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
  assert.equal(hidden(document.querySelector("#search")), false);
});

test("hides app-install prompts and leaves the login link and sponsored store links", () => {
  const { document } = mount(feedHTML);
  assert.equal(hidden(document.querySelector("#use-app-bar")), true);
  assert.equal(hidden(document.querySelector("#open-app")), true);
  assert.equal(hidden(document.querySelector("#get-app")), true);
  assert.equal(hidden(document.querySelector("#open-ig")), true);
  assert.equal(hidden(document.querySelector("#login-link")), false);
  assert.equal(hidden(document.querySelector("#ad-store")), false);
  assert.equal(hidden(document.querySelector("#ad-store-link")), false);
  assert.equal(document.querySelector("#ad-store").classList.contains("enough-keep"), true);
});

test("install prompts stay hidden when the other toggles are off", () => {
  const { document, engine } = mount(feedHTML);
  engine.applyToggles({ hideReels: false, hideExplore: false, hideSuggested: false });
  assert.equal(hidden(document.querySelector("#open-app")), true);
  assert.equal(hidden(document.querySelector("#get-app")), true);
  assert.equal(hidden(document.querySelector("#ad")), false);
});

test("stylesheet text keeps an exception for ads", () => {
  const { document } = mount(feedHTML);
  const css = document.getElementById("enough-hide-style").textContent;
  assert.match(css, /\.enough-hidden/);
  assert.match(css, /:not\(\.enough-keep\)/);
  assert.match(css, /apps\.apple\.com/);
  assert.match(css, /\.enough-keep a\[href\*="apps\.apple\.com"\]/);
  assert.equal(css, hideCSS());
});

test("profile button clicks the profile link and does not report the username", () => {
  const { document, engine, events } = mount(feedHTML);
  let clicked = null;
  const profile = document.querySelector("a[href='/ada.lovelace/']");
  profile.addEventListener("click", (event) => {
    clicked = profile.getAttribute("href");
    event.preventDefault();
  });
  assert.equal(engine.openProfile(), true);
  assert.equal(clicked, "/ada.lovelace/");
  const dumped = JSON.stringify(events);
  assert.equal(dumped.includes("ada.lovelace"), false);
  assert.equal(dumped.includes("POST1"), false);
});

test("history changes report a path and not a document", () => {
  const { dom, document, events } = mount(feedHTML);
  dom.window.history.pushState({}, "", "/direct/inbox/");
  const routes = events.filter((event) => event.type === "route");
  assert.equal(routes.at(-1).path, "/direct/inbox/");
  assert.equal(document.documentElement.getAttribute("data-enough-route"), "direct");
  assert.equal(Object.hasOwn(routes.at(-1), "html"), false);
});

test("classifyPath matches the shared route fixture", () => {
  const routes = JSON.parse(read("Tests/FilterEngineTests/Fixtures/routes.json"));
  for (const route of routes) {
    assert.equal(classifyPath(route.path), route.surface, route.path);
  }
});

test("the following feed stays visible, including posts from people you follow", () => {
  const html = `<main id="feed">
    <article id="a"><a href="/p/AAA111/">a</a></article>
    <article id="b"><a href="/reel/BBB222/">b</a></article>
    <article id="c"><a href="/p/CCC333/">c</a></article>
    <section id="sug"><h2>Suggested for you</h2><button type="button">Follow</button><button type="button">Follow</button></section>
  </main>`;
  const { document } = mount(html);
  assert.equal(hidden(document.querySelector("#feed")), false);
  assert.equal(hidden(document.querySelector("#a")), false);
  assert.equal(hidden(document.querySelector("#b")), false);
  assert.equal(hidden(document.querySelector("#c")), false);
  assert.equal(hidden(document.querySelector("#sug")), true);
});

test("already seen posts collapse and a feed of only those is caught up", () => {
  const html = `<main>
    <article id="old1"><a href="/p/OLD1/">old</a></article>
    <article id="old2"><a href="/reel/OLD2/">old reel</a></article>
  </main>`;
  const { document, events } = mount(html, "https://www.instagram.com/?variant=following", null, {
    seen: ["p/OLD1", "reel/OLD2"],
  });
  assert.equal(document.querySelector("#old1").classList.contains("enough-seen"), true);
  assert.equal(document.querySelector("#old2").classList.contains("enough-seen"), true);
  assert.equal(document.querySelector("#old1").getAttribute("data-enough-observed"), null);
  assert.equal(events.some((event) => event.type === "caughtUp"), true);
});

test("an unseen post stays on screen", () => {
  const html = `<main>
    <article id="old"><a href="/p/OLD1/">old</a></article>
    <article id="fresh"><a href="/p/NEW1/">new</a></article>
  </main>`;
  const { document, events } = mount(html, "https://www.instagram.com/?variant=following", null, {
    seen: ["p/OLD1"],
  });
  assert.equal(document.querySelector("#old").classList.contains("enough-seen"), true);
  assert.equal(hidden(document.querySelector("#fresh")), false);
  assert.equal(document.querySelector("#fresh").getAttribute("data-enough-observed"), "1");
  assert.equal(events.some((event) => event.type === "caughtUp"), false);
  assert.equal(events.some((event) => event.type === "hasUnseen"), true);
});

test("personal mode hides in-feed sponsored labels and leaves other posts", () => {
  const { document } = mount(feedHTML, "https://www.instagram.com/?variant=following", null, {
    hideSponsored: true,
  });
  assert.equal(hidden(document.querySelector("#ad")), true);
  assert.equal(hidden(document.querySelector("#ad-text")), true);
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), false);
  assert.equal(hidden(document.querySelector("#organic")), false);
  assert.equal(hidden(document.querySelector("#reel")), false);
});

test("the default build leaves sponsored posts on screen and does not block requests", () => {
  const source = fs.readFileSync(enginePath, "utf8");
  assert.equal(source.includes("webRequest"), false);
  assert.equal(source.includes("declarativeNetRequest"), false);
  assert.equal(source.includes("block("), false);
  const { document } = mount(feedHTML);
  assert.equal(hidden(document.querySelector("#ad")), false);
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
  assert.equal(hidden(document.querySelector("#ad-text")), false);
});

test("captured home keeps the post, stories, and caption and hides follow rows", () => {
  const html = fs.readFileSync(path.join(__dirname, "fixtures/captured-home.html"), "utf8");
  const { document } = mount(html, "https://www.instagram.com/?variant=following");
  assert.equal(hidden(document.querySelector("#column")), false);
  assert.equal(hidden(document.querySelector("#stories")), false);
  assert.equal(hidden(document.querySelector("#post")), false);
  assert.equal(hidden(document.querySelector("#media")), false);
  assert.equal(hidden(document.querySelector("#caption")), false);
  assert.equal(hidden(document.querySelector("#actions")), false);
  assert.equal(hidden(document.querySelector("#suggestions")), true);
  assert.equal(hidden(document.querySelector("a[href='/reels/']")), true);
  assert.equal(hidden(document.querySelector("a[href='/direct/inbox/']")), false);
});

test("the bundled script starts from the boot payload and does not eval remote code", () => {
  const source = fs.readFileSync(enginePath, "utf8");
  assert.equal(source.includes("eval("), false);
  assert.equal(source.includes("new Function"), false);
  const dom = new JSDOM(feedHTML, {
    url: "https://www.instagram.com/",
    runScripts: "outside-only",
  });
  dom.window.__ENOUGH_BOOT__ = {
    config: selectorConfig(),
    toggles: { hideReels: true, hideExplore: true, hideSuggested: true },
    css: hideCSS(),
  };
  dom.window.eval(source);
  assert.equal(hidden(dom.window.document.querySelector("a[href='/reels/']")), true);
  assert.equal(hidden(dom.window.document.querySelector("#ad")), false);
});

test("hides the whole tab slot so the bottom bar has no gap", () => {
  const html = `<!doctype html><html><body><main><article></article></main>
    <div id="bar">
      <div class="slot" id="home"><span><a href="/">Home</a></span></div>
      <div class="slot" id="reels-slot"><span><a href="/reels/">Reels</a></span></div>
      <div class="slot" id="dm"><span><a href="/direct/inbox/">Messages</a></span></div>
    </div></body></html>`;
  const { document } = mount(html);
  assert.equal(hidden(document.querySelector("#reels-slot")), true);
  assert.equal(hidden(document.querySelector("#home")), false);
  assert.equal(hidden(document.querySelector("#dm")), false);
  assert.equal(hidden(document.querySelector("#bar")), false);
});

test("a home URL without a query does not redirect", () => {
  const html = `<!doctype html><html><body><main></main></body></html>`;
  const { dom } = mount(html, "https://www.instagram.com/", null, { followingURL: "https://www.instagram.com/" });
  assert.equal(dom.window.location.href, "https://www.instagram.com/");
});

test("a home feed of only hidden suggestions shows the caught-up notice in the feed", () => {
  const html = `<!doctype html><html><body><main>
    <div id="col"><section role="region"><h2>Suggestions for you</h2>
      <div><a href="/someone/">someone</a><button>Follow</button></div>
      <div><a href="/other/">other</a><button>Follow</button></div></section></div>
    </main><nav id="tabs"><a href="/">Home</a></nav></body></html>`;
  const { document, events } = mount(html, "https://www.instagram.com/");
  assert.ok(events.some((e) => e.type === "caughtUp"));
  const notice = document.getElementById("enough-notice");
  assert.ok(notice);
  assert.equal(notice.getAttribute("data-mode"), "caught");
  assert.equal(hidden(document.querySelector("#tabs")), false);
});

test("at the cap the feed shows the cap notice and keeps the tab bar", () => {
  const { document, engine } = mount(feedHTML, "https://www.instagram.com/");
  engine.setCapState(true, "6:00 AM");
  const notice = document.getElementById("enough-notice");
  assert.equal(notice.getAttribute("data-mode"), "cap");
  assert.match(notice.textContent, /6:00 AM/);
  assert.equal(document.documentElement.classList.contains("enough-at-cap"), true);
  assert.equal(hidden(document.querySelector("a[href='/direct/inbox/']")), false);
  engine.setCapState(false, "");
  assert.equal(document.documentElement.classList.contains("enough-at-cap"), false);
});

test("the notice is not shown off the feed", () => {
  const { document, engine } = mount(feedHTML, "https://www.instagram.com/direct/inbox/");
  engine.setCapState(true, "6:00 AM");
  assert.equal(document.getElementById("enough-notice"), null);
});

test("at the cap an opened post shows only that post, not the list of more posts", () => {
  const html = `<!doctype html><html><body><main>
    <article id="opened"><a href="/p/OPEN1/"><img src="a.jpg"></a></article>
    <article id="more1"><a href="/p/MORE1/"><img src="b.jpg"></a></article>
    <article id="more2"><a href="/p/MORE2/"><img src="c.jpg"></a></article>
    </main></body></html>`;
  const { document, engine } = mount(html, "https://www.instagram.com/p/OPEN1/");
  engine.setCapState(true, "6:00 AM");
  assert.equal(document.querySelector("#opened").classList.contains("enough-cap-hidden"), false);
  assert.equal(document.querySelector("#more1").classList.contains("enough-cap-hidden"), true);
  assert.equal(document.querySelector("#more2").classList.contains("enough-cap-hidden"), true);
  engine.setCapState(false, "");
  assert.equal(document.querySelector("#more1").classList.contains("enough-cap-hidden"), false);
});

test("profile opens from a page with no tab bar using the path remembered in this page only", () => {
  const { dom, engine, events } = mount(feedHTML);
  const saved = dom.window.sessionStorage.getItem("enough-profile-path");
  assert.equal(saved, "/ada.lovelace/");
  dom.window.history.pushState({}, "", "/direct/inbox/");
  for (const a of dom.window.document.querySelectorAll("a[href='/ada.lovelace/']")) a.remove();
  assert.equal(engine.openProfile(), true);
  assert.equal(dom.window.location.pathname, "/ada.lovelace/");
  // Page paths are reported on every navigation; nothing else carries the username.
  const others = events.filter((e) => e.type !== "route");
  assert.equal(JSON.stringify(others).includes("ada.lovelace"), false);
});

test("the page reports ready once it has its layout", () => {
  const { events } = mount(feedHTML);
  assert.equal(events.filter((e) => e.type === "ready").length, 1);
});

test("an ad labelled just \"Ad\" is kept on screen and never counts", () => {
  const html = `<!doctype html><html><body><main>
    <article id="ad"><header><a href="/brand/?entry_point=feed&a_mpk=123">brand</a><span>Ad</span></header>
      <a href="/p/ADPOST/"><img src="a.jpg"></a><a href="https://example.com">Buy tickets</a></article>
    <article id="post"><header><a href="/friend/">friend</a></header><a href="/p/FRIEND1/"><img src="b.jpg"></a></article>
    </main></body></html>`;
  const { document, io, events } = mount(html, "https://www.instagram.com/");
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
  assert.equal(hidden(document.querySelector("#ad")), false);
  io.fire(document.querySelector("#ad"), 1);
  io.fire(document.querySelector("#post"), 1);
  const counted = events.filter((e) => e.type === "postViewed").map((e) => e.permalink);
  assert.deepEqual(counted, ["p/FRIEND1"]);
});

test("an ad found only by its tracking link is kept and not counted", () => {
  const html = `<!doctype html><html><body><main>
    <article id="ad"><a href="/brand/?a_mpk=99">brand</a><a href="/p/ADPOST2/"><img src="a.jpg"></a></article>
    </main></body></html>`;
  const { document } = mount(html, "https://www.instagram.com/");
  assert.equal(document.querySelector("#ad").classList.contains("enough-keep"), true);
});

test("on home, a post with a Follow button is a suggestion and is hidden", () => {
  const html = `<!doctype html><html><body><main>
    <article id="stranger"><header><a href="/stranger/">stranger</a><div role="button">Follow</div></header>
      <a href="/p/STRANGE1/"><img src="a.jpg"></a></article>
    <article id="friend"><header><a href="/friend/">friend</a></header>
      <a href="/p/FRIEND2/"><img src="b.jpg"></a><span>Following</span></article>
    </main></body></html>`;
  const { document, io } = mount(html, "https://www.instagram.com/");
  assert.equal(hidden(document.querySelector("#stranger")), true);
  assert.equal(hidden(document.querySelector("#friend")), false);
  assert.deepEqual(io.elements.map((e) => e.id), ["friend"]);
});

test("a Follow button on a profile page does not hide that profile's posts", () => {
  const html = `<!doctype html><html><body><main>
    <article id="p"><header><a href="/someone/">someone</a><button>Follow</button></header>
      <a href="/p/SOME1/"><img src="a.jpg"></a></article></main></body></html>`;
  const { document } = mount(html, "https://www.instagram.com/someone/");
  assert.equal(hidden(document.querySelector("#p")), false);
});

test("nothing counts once the cap is reached", () => {
  const { document, io, engine, events } = mount(feedHTML, "https://www.instagram.com/");
  engine.setCapState(true, "6:00 AM");
  io.fire(document.querySelector("#organic"), 1);
  assert.equal(events.filter((e) => e.type === "postViewed").length, 0);
});

test("your own posts never count toward the cap", () => {
  const html = `<!doctype html><html><body><main>
    <article id="mine"><header><a href="/ada.lovelace/">ada.lovelace</a></header><a href="/p/MINE1/"><img src="m.jpg"></a></article>
    <article id="friend"><header><a href="/friend/">friend</a></header><a href="/p/FRIEND2/"><img src="f.jpg"></a></article>
    </main>
    <nav><a href="/">Home</a><a href="/explore/">Explore</a><a href="/direct/inbox/">Messages</a><a href="/ada.lovelace/">Profile</a></nav>
    </body></html>`;
  const { document, io, events } = mount(html, "https://www.instagram.com/");
  io.fire(document.querySelector("#mine"), 1);
  io.fire(document.querySelector("#friend"), 1);
  const counted = events.filter((e) => e.type === "postViewed").map((e) => e.permalink);
  assert.deepEqual(counted, ["p/FRIEND2"]);
  assert.equal(document.querySelector("#mine").getAttribute("data-enough-own"), "1");
});

test("in-page navigation gives the router a fresh history entry each time", () => {
  const { dom, engine } = mount(feedHTML, "https://www.instagram.com/");
  const keys = [];
  dom.window.addEventListener("popstate", (e) => keys.push(e.state && e.state.key));
  assert.equal(engine.navigate("/direct/inbox/"), true);
  assert.equal(dom.window.location.pathname, "/direct/inbox/");
  assert.equal(engine.navigate("/"), true);
  assert.equal(dom.window.location.pathname, "/");
  assert.equal(keys.length, 2);
  assert.match(keys[0], /^state-key-\d+-\d+$/);
  assert.notEqual(keys[0], keys[1]);
  assert.equal(engine.navigate("javascript:alert(1)"), false);
  assert.equal(engine.navigate("https://example.com/"), false);
});
