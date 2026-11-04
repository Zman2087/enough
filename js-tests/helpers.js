const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const root = path.join(__dirname, "..");
const enginePath = path.join(root, "Sources/FilterEngine/Resources/filter.js");
const { createEngine, classifyPath, permalinkOf } = require(enginePath);

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

function selectorConfig() {
  return JSON.parse(read("Sources/FilterEngine/Resources/selectors.json"));
}

function hideCSS() {
  return read("Sources/FilterEngine/Resources/hide.css");
}

class FakeIO {
  constructor(callback, options) {
    this.callback = callback;
    this.options = options;
    this.elements = [];
    FakeIO.latest = this;
  }

  observe(element) {
    this.elements.push(element);
  }

  unobserve(element) {
    this.elements = this.elements.filter((item) => item !== element);
  }

  disconnect() {
    this.elements = [];
  }

  fire(element, ratio) {
    this.callback(
      [{ target: element, intersectionRatio: ratio, isIntersecting: ratio >= 0.5 }],
      this
    );
  }
}

function mount(html, url, toggles, extra) {
  const events = [];
  const dom = new JSDOM(html, { url: url || "https://www.instagram.com/" });
  const engine = createEngine({
    document: dom.window.document,
    config: selectorConfig(),
    toggles: toggles || { hideReels: true, hideExplore: true, hideSuggested: true },
    cssText: hideCSS(),
    seen: (extra && extra.seen) || [],
    followingURL: (extra && extra.followingURL) || "",
    hideSponsored: !!(extra && extra.hideSponsored),
    onEvent: (payload) => events.push(payload),
    IntersectionObserver: FakeIO,
  });
  engine.start();
  return { dom, engine, events, document: dom.window.document, io: FakeIO.latest };
}

function hidden(element) {
  return element.classList.contains("enough-hidden")
    || element.classList.contains("enough-seen")
    || element.classList.contains("enough-route-hidden");
}

module.exports = {
  FakeIO,
  classifyPath,
  createEngine,
  enginePath,
  hidden,
  hideCSS,
  mount,
  permalinkOf,
  read,
  selectorConfig,
};
