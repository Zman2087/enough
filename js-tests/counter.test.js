const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { permalinkOf, mount } = require("./helpers");

const feedHTML = fs.readFileSync(path.join(__dirname, "fixtures/feed.html"), "utf8");

function views(events) {
  return events.filter((event) => event.type === "postViewed");
}

test("permalinks keep only the shortcode", () => {
  assert.equal(permalinkOf("/p/AbC123/"), "p/AbC123");
  assert.equal(permalinkOf("/reel/XYZ/?igsh=1"), "reel/XYZ");
  assert.equal(permalinkOf("https://www.instagram.com/p/AbC123/"), "p/AbC123");
  assert.equal(permalinkOf("/ada.lovelace/"), null);
  assert.equal(permalinkOf("javascript:alert(1)"), null);
});

test("a post counts once when half of it is visible", () => {
  const { document, events, io } = mount(feedHTML);
  const organic = document.querySelector("#organic");
  assert.deepEqual(io.options.threshold, [0.5]);
  io.fire(organic, 0.49);
  assert.equal(views(events).length, 0);
  io.fire(organic, 0.5);
  assert.deepEqual(views(events), [{ type: "postViewed", permalink: "p/POST1" }]);
  io.fire(organic, 1);
  assert.equal(views(events).length, 1);
  assert.equal(organic.getAttribute("data-enough-counted"), "1");
});

test("the same permalink on a second article does not count again", () => {
  const { document, events, io } = mount(feedHTML);
  io.fire(document.querySelector("#organic"), 0.8);
  const extra = document.createElement("article");
  extra.id = "dup";
  extra.innerHTML = '<a href="/p/POST1/?utm=1">again</a>';
  document.body.appendChild(extra);
  return new Promise((resolve) => setTimeout(resolve, 30)).then(() => {
    assert.equal(extra.classList.contains("enough-seen"), true);
    assert.equal(extra.getAttribute("data-enough-observed"), null);
    io.fire(extra, 1);
    assert.equal(views(events).length, 1);
  });
});

test("a post inserted later is observed and can count", () => {
  const { document, events, io } = mount(feedHTML);
  document.getElementById("later").innerHTML = '<article id="new"><a href="/p/NEW1/">new</a></article>';
  return new Promise((resolve) => setTimeout(resolve, 30)).then(() => {
    const article = document.getElementById("new");
    assert.equal(article.getAttribute("data-enough-key"), "p/NEW1");
    assert.equal(article.getAttribute("data-enough-observed"), "1");
    io.fire(article, 0.75);
    assert.deepEqual(views(events), [{ type: "postViewed", permalink: "p/NEW1" }]);
  });
});

test("sponsored posts are not counted even if an observer is forced", () => {
  const { document, events, io } = mount(feedHTML);
  const ad = document.querySelector("#ad");
  io.fire(ad, 1);
  assert.equal(views(events).length, 0);
  assert.equal(ad.classList.contains("enough-keep"), true);
});
