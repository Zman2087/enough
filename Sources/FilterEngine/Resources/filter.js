/*
 * Enough feed filter.
 * Bundled with the app. It hides Reels, Explore, and suggested posts.
 * It does not hide ads, does not read a password, and does not send the page anywhere.
 * A post counts once, when half of it is on screen, by its permalink shortcode.
 */
(function (root, factory) {
  "use strict";
  var api = factory(root);
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.EnoughFilter = api;
  if (typeof document !== "undefined" && root.__ENOUGH_BOOT__ && root.__ENOUGH_BOOT__.config) {
    var boot = root.__ENOUGH_BOOT__;
    var engine = api.createEngine({
      document: document,
      config: boot.config,
      toggles: boot.toggles,
      cssText: boot.css || "",
      seen: boot.seen || [],
      followingURL: boot.homeURL || "",
      hideSponsored: !!boot.hideSponsored,
      cap: root.__ENOUGH_CAP__ || null
    });
    engine.start();
    root.Enough = engine;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function (root) {
  "use strict";

  var SEARCH_PATH = "/explore/search/";

  var RESERVED = {
    about: 1, accounts: 1, ar: 1, challenge: 1, clips: 1, developer: 1,
    direct: 1, directory: 1, emails: 1, explore: 1, fxcal: 1, legal: 1,
    live: 1, login: 1, nametag: 1, oauth: 1, p: 1, privacy: 1, reel: 1,
    reels: 1, share: 1, stories: 1, terms: 1, tv: 1
  };

  var PROFILE_SUB = {
    channel: 1, followers: 1, following: 1, saved: 1, tagged: 1
  };

  var NEVER_HIDE = {
    HTML: 1, BODY: 1, HEAD: 1, SCRIPT: 1, STYLE: 1, LINK: 1, META: 1
  };

  function classifyPath(pathname) {
    var path = pathname || "/";
    var bare = String(path).split("?")[0].split("#")[0];
    var parts = bare.split("/").filter(Boolean);
    if (parts.length === 0) return "feed";
    var first = parts[0].toLowerCase();
    if (first === "reels" || first === "reel") return "reels";
    if (first === "stories") return "stories";
    if (first === "direct") return "direct";
    if (first === "explore") {
      if (parts.length >= 2 && parts[1].toLowerCase() === "search") return "search";
      return "explore";
    }
    if (first === "accounts" || first === "login") return "login";
    if (first === "p") return "post";
    if (parts.length >= 2 && parts[1].toLowerCase() === "reels" && !RESERVED[first]) return "reels";
    if (parts.length === 1 && !RESERVED[first]) return "profile";
    if (parts.length === 2 && PROFILE_SUB[parts[1].toLowerCase()] && !RESERVED[first]) return "profile";
    return "other";
  }

  function permalinkOf(href) {
    if (!href || typeof href !== "string") return null;
    var match = href.match(/\/(p|reel)\/([A-Za-z0-9_-]{1,64})(?=[/?#]|$)/);
    if (!match) return null;
    return match[1] + "/" + match[2];
  }

  function createEngine(options) {
    options = options || {};
    var doc = options.document;
    var config = options.config || {};
    var toggles = normalizeToggles(options.toggles);
    var cssText = options.cssText || "";
    var onEvent = options.onEvent;
    var seen = new Set();
    var alreadySeen = new Set(options.seen || []);
    var followingURL = options.followingURL || "";
    var hideSponsored = !!options.hideSponsored;
    var observed = new WeakSet();
    var io = null;
    var mo = null;
    var started = false;
    var historyHooked = false;
    var pending = [];
    var scanScheduled = false;
    var statusTimer = 0;
    var lastFeedState = "";
    var didRedirect = false;
    var capState = { reached: !!(options.cap && options.cap.reached), resetText: (options.cap && options.cap.resetText) || "" };
    var NOTICE_ID = "enough-notice";
    var readySent = false;
    var PROFILE_KEY = "enough-profile-path";

    function normalizeToggles(value) {
      value = value || {};
      return {
        hideReels: !!value.hideReels,
        hideExplore: !!value.hideExplore,
        hideSuggested: !!value.hideSuggested
      };
    }

    function emit(payload) {
      if (typeof onEvent === "function") {
        try { onEvent(payload); } catch (err) { /* tests and native stay independent */ }
      }
      var handler = nativeHandler();
      if (!handler) return;
      try { handler.postMessage(payload); } catch (err) { /* page must keep working */ }
    }

    function nativeHandler() {
      var views = [doc && doc.defaultView, root];
      for (var i = 0; i < views.length; i++) {
        var view = views[i];
        if (!view || !view.webkit || !view.webkit.messageHandlers) continue;
        var handler = view.webkit.messageHandlers.enough;
        if (handler && typeof handler.postMessage === "function") return handler;
      }
      return null;
    }

    function installCSS() {
      if (!cssText || !doc) return;
      var el = doc.getElementById("enough-hide-style");
      if (!el) {
        el = doc.createElement("style");
        el.id = "enough-hide-style";
        var parent = doc.head || doc.documentElement;
        if (!parent) return;
        parent.appendChild(el);
      }
      el.textContent = cssText;
    }

    function matches(el, selector) {
      try {
        return !!(el && el.matches && selector && el.matches(selector));
      } catch (err) {
        return false;
      }
    }

    function queryAll(scope, selector) {
      try {
        if (!scope || !scope.querySelectorAll || !selector) return [];
        return scope.querySelectorAll(selector);
      } catch (err) {
        return [];
      }
    }

    function collect(scope, selector) {
      var out = [];
      if (!scope || !selector) return out;
      if (scope.nodeType === 1 && matches(scope, selector)) out.push(scope);
      var found = queryAll(scope, selector);
      for (var i = 0; i < found.length; i++) out.push(found[i]);
      return out;
    }

    function patterns(kind) {
      var text = config.text || {};
      return text[kind] || [];
    }

    function textEquals(text, pattern) {
      return String(text).toLowerCase() === String(pattern).toLowerCase();
    }

    function isSponsoredLabel(el) {
      if (!el || el.nodeType !== 1) return false;
      if (el.childElementCount > 1) return false;
      var text = (el.textContent || "").replace(/\s+/g, " ").trim();
      if (!text || text.length > 40) return false;
      var list = patterns("sponsored");
      for (var i = 0; i < list.length; i++) {
        if (textEquals(text, list[i])) return true;
      }
      return false;
    }

    function matchesSponsoredSelector(el) {
      var list = (config.posts && config.posts.sponsored) || [];
      for (var i = 0; i < list.length; i++) {
        if (matches(el, list[i])) return true;
      }
      return false;
    }

    function containsSponsored(el) {
      if (!el || el.nodeType !== 1) return false;
      if (isSponsoredLabel(el) || matchesSponsoredSelector(el)) return true;
      var selectors = (config.posts && config.posts.sponsored) || [];
      for (var i = 0; i < selectors.length; i++) {
        if (queryAll(el, selectors[i]).length > 0) return true;
      }
      var nodes = queryAll(el, "span, a, button");
      var limit = Math.min(nodes.length, 24);
      for (var n = 0; n < limit; n++) {
        if (isSponsoredLabel(nodes[n])) return true;
      }
      return false;
    }

    function isPostContainer(el) {
      var list = (config.posts && config.posts.containers) || [];
      for (var i = 0; i < list.length; i++) {
        if (matches(el, list[i])) return true;
      }
      return false;
    }

    function isAdUnit(el) {
      if (!el || el.nodeType !== 1) return false;
      if (matchesSponsoredSelector(el) || isSponsoredLabel(el)) return true;
      if (isPostContainer(el) && containsSponsored(el)) return true;
      return false;
    }

    function markKeep(el) {
      if (el && el.classList) el.classList.add("enough-keep");
    }

    function hasKeepAncestor(el) {
      var parent = el && el.parentElement;
      while (parent) {
        if (parent.classList && parent.classList.contains("enough-keep")) return true;
        parent = parent.parentElement;
      }
      return false;
    }

    function markAdUnits(scope) {
      var containers = (config.posts && config.posts.containers) || [];
      var selectors = (config.posts && config.posts.sponsored) || [];
      var i;
      for (i = 0; i < containers.length; i++) {
        var nodes = collect(scope, containers[i]);
        for (var n = 0; n < nodes.length; n++) {
          if (isAdUnit(nodes[n])) classifyAd(nodes[n]);
        }
      }
      for (i = 0; i < selectors.length; i++) {
        var marked = collect(scope, selectors[i]);
        for (var m = 0; m < marked.length; m++) classifyAd(marked[m]);
      }
    }

    // Personal builds hide the post itself from its label. They do not block requests.
    function classifyAd(el) {
      if (!el || !el.classList) return;
      if (hideSponsored && isPostContainer(el)) {
        el.classList.remove("enough-keep");
        el.classList.add("enough-hidden");
        return;
      }
      markKeep(el);
    }

    function canHide(el) {
      if (!el || el.nodeType !== 1) return false;
      if (NEVER_HIDE[el.tagName]) return false;
      return true;
    }

    function isSearchLink(el) {
      if (!el || !el.getAttribute) return false;
      var href = el.getAttribute("href") || "";
      return href.indexOf("/explore/search") !== -1;
    }

    function isFeedShell(el) {
      if (!el || el.nodeType !== 1) return true;
      var tag = el.tagName;
      if (tag === "MAIN" || tag === "NAV" || tag === "HEADER") return true;
      var role = el.getAttribute && el.getAttribute("role");
      return role === "main" || role === "navigation";
    }

    function hideElement(el) {
      if (!canHide(el)) return;
      if (isFeedShell(el)) return;
      if (isSearchLink(el)) return;
      if (el.classList && (el.classList.contains("enough-keep") || hasKeepAncestor(el))) return;
      if (isAdUnit(el)) {
        if (hideSponsored && isPostContainer(el)) {
          el.classList.remove("enough-keep");
          el.classList.add("enough-hidden");
        } else if (!hideSponsored) {
          markKeep(el);
        }
        return;
      }
      if (containsSponsored(el)) {
        var children = el.children || [];
        for (var i = 0; i < children.length; i++) hideElement(children[i]);
        return;
      }
      el.classList.add("enough-hidden");
    }

    function permalinkFrom(container) {
      var list = (config.posts && config.posts.permalink) || [];
      for (var i = 0; i < list.length; i++) {
        var node = null;
        if (matches(container, list[i])) node = container;
        else {
          var found = queryAll(container, list[i]);
          node = found[0] || null;
        }
        if (!node) continue;
        var href = node.getAttribute("href") || "";
        var key = permalinkOf(href);
        if (key) return key;
      }
      return null;
    }

    // A tab link sits inside fixed-width wrappers. Hiding only the link leaves an empty
    // slot in the bottom bar, so climb to the outermost wrapper that holds no other link.
    function tabSlot(el) {
      var current = el;
      var hops = 0;
      while (current && current.parentElement && hops < 6) {
        var parent = current.parentElement;
        if (isFeedShell(parent) || NEVER_HIDE[parent.tagName]) break;
        if (parent.childElementCount > 2) break;
        if (parent.querySelectorAll && parent.querySelectorAll("a, [role='button']").length > 1) break;
        current = parent;
        hops += 1;
      }
      return current;
    }

    // The Explore tab is kept but sends you to the search page, which has no grid of posts or Reels.
    function retargetToSearch(el) {
      if (!el || !el.setAttribute) return;
      if (el.getAttribute("data-enough-search") === "1") return;
      el.setAttribute("data-enough-search", "1");
      el.setAttribute("data-enough-href", el.getAttribute("href") || "");
      el.setAttribute("href", SEARCH_PATH);
    }

    function applySelectors(scope) {
      var hide = config.hide || {};
      var plain = [].concat(hide.install || []);
      if (toggles.hideSuggested) plain = plain.concat(hide.suggested || []);
      for (var i = 0; i < plain.length; i++) {
        var nodes = collect(scope, plain[i]);
        for (var n = 0; n < nodes.length; n++) hideElement(nodes[n]);
      }
      if (toggles.hideReels) {
        var reels = hide.reels || [];
        for (var r = 0; r < reels.length; r++) {
          var reelNodes = collect(scope, reels[r]);
          for (var k = 0; k < reelNodes.length; k++) hideElement(tabSlot(reelNodes[k]));
        }
      }
      if (toggles.hideExplore) {
        var explore = hide.explore || [];
        for (var e = 0; e < explore.length; e++) {
          var exploreNodes = collect(scope, explore[e]);
          for (var x = 0; x < exploreNodes.length; x++) retargetToSearch(exploreNodes[x]);
        }
      }
    }

    function isSuggestedLabel(el) {
      if (!el || el.nodeType !== 1) return false;
      if (el.childElementCount > 2) return false;
      var text = (el.textContent || "").replace(/\s+/g, " ").trim();
      if (!text || text.length > 60) return false;
      var list = patterns("suggested");
      for (var i = 0; i < list.length; i++) {
        if (textEquals(text, list[i])) return true;
      }
      return false;
    }

    function suggestedRegion(el) {
      var current = el;
      var hops = 0;
      while (current && hops < 6) {
        var tag = current.tagName;
        if (tag === "SECTION" || tag === "ARTICLE" || (current.getAttribute && current.getAttribute("role") === "region")) {
          return current;
        }
        current = current.parentElement;
        hops += 1;
      }
      return (el && el.parentElement) || el;
    }

    function labelText(el) {
      return String((el && el.textContent) || "")
        .replace(/[\u200b\ufeff]/g, "")
        .replace(/\s+/g, " ")
        .trim()
        .replace(/\s*[×✕✖]\s*$/g, "")
        .trim();
    }

    function matchesPhrase(text, list) {
      if (!text || text.length > 80) return false;
      for (var i = 0; i < list.length; i++) {
        if (textEquals(text, list[i])) return true;
      }
      return false;
    }

    function isInstallLabel(el) {
      if (!el || el.nodeType !== 1) return false;
      if (el.childElementCount > 8) return false;
      return matchesPhrase(labelText(el), patterns("install"));
    }

    function bannerTarget(el) {
      var current = el;
      var hops = 0;
      while (current && current.parentElement && hops < 5) {
        var parent = current.parentElement;
        if (isFeedShell(parent) || NEVER_HIDE[parent.tagName]) break;
        if (parent.querySelector && parent.querySelector("article, nav, a[href^='/direct']")) break;
        if (labelText(parent).length > 80) break;
        current = parent;
        hops += 1;
      }
      return current;
    }

    function markInstallPrompts(scope) {
      var nodes = queryAll(scope, "a, button, [role='button']");
      var list = [];
      if (scope && scope.nodeType === 1) list.push(scope);
      for (var i = 0; i < nodes.length; i++) list.push(nodes[i]);
      for (var n = 0; n < list.length; n++) {
        var el = list[n];
        if (!isInstallLabel(el)) continue;
        if (el.classList && (el.classList.contains("enough-keep") || hasKeepAncestor(el))) continue;
        var target = bannerTarget(el);
        if (!target || isFeedShell(target)) continue;
        if (target.classList && (target.classList.contains("enough-keep") || hasKeepAncestor(target))) continue;
        hideElement(target);
      }
    }

    function containsRealPost(el) {
      if (!el || !el.querySelector) return false;
      if (!el.querySelector("img, video")) return false;
      var links = el.querySelectorAll("a[href*='/p/'], a[href*='/reel/']");
      return links.length > 0;
    }

    function followButtonCount(el) {
      var nodes = el.querySelectorAll ? el.querySelectorAll("button, [role='button']") : [];
      var count = 0;
      var limit = Math.min(nodes.length, 30);
      for (var i = 0; i < limit; i++) {
        var text = labelText(nodes[i]);
        if (text === "Follow" || text === "Following") count += 1;
      }
      return count;
    }

    function isSuggestionModule(el) {
      if (!el || el === doc.body || isFeedShell(el)) return false;
      var text = labelText(el).toLowerCase();
      var labels = patterns("suggested");
      var named = false;
      for (var i = 0; i < labels.length; i++) {
        if (text.indexOf(String(labels[i]).toLowerCase()) !== -1) { named = true; break; }
      }
      if (!named) return false;
      if (followButtonCount(el) < 2) return false;
      if (containsRealPost(el)) return false;
      return true;
    }

    function hideSuggestedLabel(el) {
      var current = el.parentElement;
      var hops = 0;
      while (current && hops < 8) {
        if (isFeedShell(current) || NEVER_HIDE[current.tagName]) break;
        if (containsRealPost(current)) break;
        if (isSuggestionModule(current)) {
          current.setAttribute("data-enough-suggested", "1");
          hideElement(current);
          return;
        }
        current = current.parentElement;
        hops += 1;
      }
    }

    // A post from an account you don't follow carries its own "Follow" button.
    // Posts from people you follow never do, so on the home feed those posts are suggestions.
    function hasFollowButton(el) {
      var nodes = queryAll(el, "button, [role='button'], a, span");
      var limit = Math.min(nodes.length, 40);
      for (var i = 0; i < limit; i++) {
        if (nodes[i].childElementCount > 1) continue;
        if (labelText(nodes[i]) === "Follow") return true;
      }
      return false;
    }

    function markUnfollowedPosts(scope) {
      if (!toggles.hideSuggested || classifyPath(currentPath()) !== "feed") return;
      // The Following view only holds accounts you follow; leave it alone.
      if (currentPath().indexOf("variant=following") !== -1) return;
      var containers = (config.posts && config.posts.containers) || ["article"];
      for (var i = 0; i < containers.length; i++) {
        var nodes = collect(scope, containers[i]);
        for (var n = 0; n < nodes.length; n++) {
          var el = nodes[n];
          if (el.classList.contains("enough-keep") || isAdUnit(el)) continue;
          if (!hasFollowButton(el)) continue;
          el.setAttribute("data-enough-suggested", "1");
          hideElement(el);
        }
      }
    }

    function markSuggested(scope) {
      markUnfollowedPosts(scope);
      if (!toggles.hideSuggested) return;
      var nodes = queryAll(scope, "h1, h2, h3, h4, span");
      var list = [];
      if (scope && scope.nodeType === 1) list.push(scope);
      for (var i = 0; i < nodes.length; i++) list.push(nodes[i]);
      for (var n = 0; n < list.length; n++) {
        var el = list[n];
        if (!isSuggestedLabel(el)) continue;
        if (el.classList && (el.classList.contains("enough-keep") || hasKeepAncestor(el))) continue;
        hideSuggestedLabel(el);
      }
    }

    function collapseSeen(scope) {
      var containers = (config.posts && config.posts.containers) || ["article"];
      for (var i = 0; i < containers.length; i++) {
        var nodes = collect(scope, containers[i]);
        for (var n = 0; n < nodes.length; n++) {
          var el = nodes[n];
          if (el.classList.contains("enough-keep")) continue;
          var key = permalinkFrom(el);
          if (!key || !alreadySeen.has(key)) continue;
          el.classList.add("enough-seen");
          el.setAttribute("data-enough-key", key);
        }
      }
    }

    function currentPath() {
      var view = doc && doc.defaultView;
      if (!view || !view.location) return "/";
      return (view.location.pathname || "/") + (view.location.search || "");
    }

    function setRoute() {
      var kind = classifyPath(currentPath());
      var html = doc && doc.documentElement;
      if (html) {
        html.setAttribute("data-enough-route", kind);
        html.classList.toggle("enough-hide-reels", !!toggles.hideReels);
        html.classList.toggle("enough-hide-explore", !!toggles.hideExplore);
      }
      return kind;
    }

    function routeHidesArticles() {
      var kind = (doc.documentElement && doc.documentElement.getAttribute("data-enough-route")) || "";
      if (kind === "reels" && toggles.hideReels) return true;
      if (kind === "explore" && toggles.hideExplore) return true;
      return false;
    }

    function hideRouteArticles(scope) {
      var nodes = collect(scope, "article");
      var hide = routeHidesArticles();
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].classList.contains("enough-keep")) continue;
        if (hide) nodes[i].classList.add("enough-route-hidden");
        else nodes[i].classList.remove("enough-route-hidden");
      }
    }

    function watch(scope) {
      if (!io) return;
      var containers = (config.posts && config.posts.containers) || [];
      for (var i = 0; i < containers.length; i++) {
        var nodes = collect(scope, containers[i]);
        for (var n = 0; n < nodes.length; n++) {
          var el = nodes[n];
          if (!el.classList) continue;
          if (el.classList.contains("enough-hidden") || el.classList.contains("enough-seen") || el.classList.contains("enough-keep")) continue;
          if (hasKeepAncestor(el)) continue;
          if (hasHiddenAncestor(el)) continue;
          var key = permalinkFrom(el);
          if (!key) continue;
          el.setAttribute("data-enough-key", key);
          noteFirstPost(el);
          if (isOwnPost(el)) continue;
          if (observed.has(el)) continue;
          observed.add(el);
          el.setAttribute("data-enough-observed", "1");
          try { io.observe(el); } catch (err) { /* observer is optional */ }
        }
      }
    }

    function hasHiddenAncestor(el) {
      var parent = el && el.parentElement;
      while (parent) {
        if (parent.classList && (parent.classList.contains("enough-hidden") || parent.classList.contains("enough-seen"))) return true;
        parent = parent.parentElement;
      }
      return false;
    }

    var reportedFirstPost = false;
    function noteFirstPost(el) {
      if (reportedFirstPost || !permalinkFrom(el)) return;
      reportedFirstPost = true;
      var view = doc && doc.defaultView;
      var ms = view && view.performance && view.performance.now ? Math.round(view.performance.now()) : 0;
      emit({ type: "firstPost", ms: ms });
    }

    function clearMarks() {
      var hidden = queryAll(doc, ".enough-hidden");
      for (var i = 0; i < hidden.length; i++) hidden[i].classList.remove("enough-hidden");
      var kept = queryAll(doc, ".enough-keep");
      for (var k = 0; k < kept.length; k++) kept[k].classList.remove("enough-keep");
      var retargeted = queryAll(doc, "[data-enough-search='1']");
      for (var r = 0; r < retargeted.length; r++) {
        var original = retargeted[r].getAttribute("data-enough-href");
        if (original) retargeted[r].setAttribute("href", original);
        retargeted[r].removeAttribute("data-enough-search");
        retargeted[r].removeAttribute("data-enough-href");
      }
    }

    function feedStatus() {
      var nodes = queryAll(doc, "article");
      var unseen = 0;
      var collapsed = 0;
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.classList.contains("enough-keep") || hasKeepAncestor(el)) continue;
        var key = permalinkFrom(el);
        if (!key) continue;
        if (isOwnPost(el)) continue;
        if (el.classList.contains("enough-seen") || alreadySeen.has(key)) collapsed += 1;
        else if (!el.classList.contains("enough-hidden") && !el.classList.contains("enough-route-hidden")) unseen += 1;
      }
      return { unseen: unseen, collapsed: collapsed };
    }

    // The cap and "caught up" are shown inside the feed column, so the site's header,
    // stories and tab bar keep working. Only the posts themselves are replaced.
    function noticeMode() {
      if (classifyPath(currentPath()) !== "feed") return null;
      if (capState.reached) return "cap";
      if (lastFeedState === "caughtUp") return "caught";
      return null;
    }

    function buildNotice(mode) {
      var box = doc.createElement("div");
      box.id = NOTICE_ID;
      box.setAttribute("data-mode", mode);
      box.setAttribute("role", "status");
      var mark = doc.createElement("div");
      mark.className = "enough-notice-mark";
      mark.setAttribute("aria-hidden", "true");
      mark.textContent = mode === "cap" ? "" : "\u2713";
      var title = doc.createElement("div");
      title.className = "enough-notice-title";
      title.textContent = mode === "cap" ? "You're done for today" : "You're all caught up";
      var body = doc.createElement("div");
      body.className = "enough-notice-body";
      if (mode === "cap") {
        body.textContent = capState.resetText
          ? "Your feed opens again at " + capState.resetText + "."
          : "Your feed opens again tomorrow.";
      } else {
        body.textContent = "You've seen all new posts from people you follow.";
      }
      box.appendChild(mark);
      box.appendChild(title);
      box.appendChild(body);
      return box;
    }

    function noticeAnchor() {
      var first = doc.querySelector("main article") || doc.querySelector("article");
      if (first && first.parentElement) return { parent: first.parentElement, before: first };
      var main = doc.querySelector("main") || doc.body;
      return main ? { parent: main, before: null } : null;
    }

    // At the cap an opened post stays readable, but the "more posts" list under it does not,
    // so a single post page can't become a second feed.
    function capTrim(scope) {
      var onPost = capState.reached && classifyPath(currentPath()) === "post";
      var current = onPost ? permalinkOf(currentPath()) : null;
      var nodes = onPost ? collect(scope || doc, "article") : queryAll(doc, "article.enough-cap-hidden");
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!onPost) {
          el.classList.remove("enough-cap-hidden");
          continue;
        }
        var key = permalinkFrom(el);
        if (key && current && key !== current) el.classList.add("enough-cap-hidden");
        else el.classList.remove("enough-cap-hidden");
      }
    }

    function renderNotice() {
      if (!doc || !doc.documentElement) return;
      var mode = noticeMode();
      var root = doc.documentElement;
      if (root.classList) root.classList.toggle("enough-at-cap", mode === "cap");
      capTrim(doc);
      var existing = doc.getElementById(NOTICE_ID);
      if (!mode) {
        if (existing && existing.parentElement) existing.parentElement.removeChild(existing);
        return;
      }
      var anchor = noticeAnchor();
      if (!anchor) return;
      if (existing && existing.getAttribute("data-mode") === mode && existing.parentElement === anchor.parent) return;
      if (existing && existing.parentElement) existing.parentElement.removeChild(existing);
      anchor.parent.insertBefore(buildNotice(mode), anchor.before);
    }

    function publishStatus() {
      var status = feedStatus();
      var next = "loading";
      // A feed with no unseen posts is caught up once it has rendered something we
      // recognise: a seen post, or a suggestions block that was hidden.
      var rendered = status.collapsed > 0 || !!doc.querySelector("[data-enough-suggested='1'].enough-hidden");
      if (rendered && status.unseen === 0) next = "caughtUp";
      else if (status.unseen > 0) next = "hasUnseen";
      if (next === lastFeedState || next === "loading") {
        renderNotice();
        return;
      }
      lastFeedState = next;
      renderNotice();
      emit({ type: next === "caughtUp" ? "caughtUp" : "hasUnseen" });
    }

    function scheduleStatus() {
      var view = doc && doc.defaultView;
      if (statusTimer && view) view.clearTimeout(statusTimer);
      var wait = function (fn) {
        if (view && view.setTimeout) statusTimer = view.setTimeout(fn, 250);
        else fn();
      };
      wait(function () {
        statusTimer = 0;
        markTabBar();
        publishStatus();
      });
    }

    function applyAll() {
      clearMarks();
      setRoute();
      markAdUnits(doc);
      applySelectors(doc);
      markInstallPrompts(doc);
      markSuggested(doc);
      hideRouteArticles(doc);
      collapseSeen(doc);
      watch(doc);
      publishStatus();
    }

    function scanNode(node) {
      if (!node || node.nodeType !== 1) return;
      if (node.id === "enough-hide-style") return;
      markAdUnits(node);
      applySelectors(node);
      markInstallPrompts(node);
      markSuggested(node);
      if (routeHidesArticles()) hideRouteArticles(node);
      collapseSeen(node);
      if (capState.reached) capTrim(node);
      watch(node);
    }

    function flushScans() {
      scanScheduled = false;
      checkReady();
      rememberProfile();
      markTabBar();
      var batch = pending;
      pending = [];
      for (var i = 0; i < batch.length; i++) scanNode(batch[i]);
      scheduleStatus();
    }

    function queueScan(node) {
      if (!node || node.nodeType !== 1 || node.id === "enough-hide-style" || node.id === NOTICE_ID) return;
      if (!readySent) checkReady();
      // A single new post is cheap and should collapse before the next paint.
      if ((node.childElementCount || 0) < 12) {
        scanNode(node);
        scheduleStatus();
        return;
      }
      pending.push(node);
      if (scanScheduled) return;
      scanScheduled = true;
      var view = doc && doc.defaultView;
      var schedule = (view && view.requestAnimationFrame) || function (fn) {
        if (view && view.setTimeout) view.setTimeout(fn, 16);
        else fn();
      };
      schedule(flushScans);
    }

    // Tells the app the page has its layout, so the launch screen can go before every
    // image and script has finished loading.
    function checkReady() {
      if (readySent || !doc || !doc.querySelector) return;
      if (!doc.querySelector("main, nav, form, [role='main']")) return;
      readySent = true;
      emit({ type: "ready" });
    }

    function storage() {
      try {
        var view = doc && doc.defaultView;
        return view && view.sessionStorage ? view.sessionStorage : null;
      } catch (err) {
        return null;
      }
    }

    // The signed-in profile link lives in the site's tab bar, next to Home and Messages.
    // Its path is kept in this page's session storage only, never sent to the app.
    function rememberProfile() {
      var inbox = doc && doc.querySelector ? doc.querySelector("a[href='/direct/inbox/']") : null;
      if (!inbox) return;
      var bar = inbox.parentElement;
      var hops = 0;
      while (bar && hops < 8 && bar.querySelectorAll("a[href]").length < 3) {
        bar = bar.parentElement;
        hops += 1;
      }
      if (!bar) return;
      var links = bar.querySelectorAll("a[href]");
      for (var i = 0; i < links.length; i++) {
        var href = links[i].getAttribute("href") || "";
        var parts = href.split("?")[0].split("#")[0].split("/").filter(Boolean);
        if (href.charAt(0) !== "/" || parts.length !== 1 || RESERVED[parts[0].toLowerCase()]) continue;
        var store = storage();
        try { if (store) store.setItem(PROFILE_KEY, "/" + parts[0] + "/"); } catch (err) { /* ignore */ }
        return;
      }
    }

    // The site's router ignores a popstate whose history state it has already handled,
    // so each in-page navigation gets a fresh entry in the router's own key format.
    var stateSerial = 0;
    function freshState() {
      stateSerial += 1;
      return { key: "state-key-" + Date.now() + "-" + stateSerial };
    }

    function pushRoute(view, path, replace) {
      var state = freshState();
      if (replace) view.history.replaceState(state, "", path);
      else view.history.pushState(state, "", path);
      var PSE = view.PopStateEvent;
      view.dispatchEvent(typeof PSE === "function" ? new PSE("popstate", { state: state }) : new view.Event("popstate"));
    }

    // Switches page inside the site, without a reload. If the page has not changed at all
    // after a moment, the router did not take it, so fall back to a normal page load.
    // The site's bottom tab bar is a fixed layer below the search header's layer, so on
    // Search the results list draws over it. Mark the bar so the stylesheet can lift it
    // there. Marking only adds a class; nothing about the bar is read or stored.
    function markTabBar() {
      if (!doc || !doc.querySelector) return;
      var existing = doc.querySelector(".enough-tabbar");
      if (existing && existing.isConnected !== false && existing.querySelector("a[href='/direct/inbox/'], a[href='/']")) return;
      var link = doc.querySelector("a[href='/direct/inbox/']") || doc.querySelector("a[href='/']");
      var view = doc.defaultView;
      if (!link || !view || !view.getComputedStyle) return;
      var el = link.parentElement;
      for (var hops = 0; el && el !== doc.body && hops < 16; hops++) {
        if (view.getComputedStyle(el).position === "fixed") {
          if (existing && existing !== el) existing.classList.remove("enough-tabbar");
          el.classList.add("enough-tabbar");
          return;
        }
        el = el.parentElement;
      }
    }

    function spaNavigate(path) {
      var view = doc && doc.defaultView;
      if (!view || !view.location) return;
      var full = "https://www.instagram.com" + path;
      var main = doc.querySelector ? doc.querySelector("main, [role='main']") : null;
      var before = main ? main.innerHTML.length : -1;
      try {
        pushRoute(view, path, false);
      } catch (err) {
        view.location.assign(full);
        return;
      }
      if (!view.setTimeout) return;
      view.setTimeout(function () {
        if (currentPath().split("?")[0] !== path) return;
        var now = doc.querySelector("main, [role='main']");
        if (now && now === main && now.isConnected && now.innerHTML.length === before) view.location.assign(full);
      }, 2500);
    }

    function ownProfilePath() {
      var store = storage();
      try { return store ? store.getItem(PROFILE_KEY) : null; } catch (err) { return null; }
    }

    // The author is the first link in the post to a single-segment profile path.
    function authorPath(el) {
      var anchors = queryAll(el, "a[href]");
      var limit = Math.min(anchors.length, 12);
      for (var i = 0; i < limit; i++) {
        var href = anchors[i].getAttribute("href") || "";
        if (href.charAt(0) !== "/") continue;
        var parts = href.split("?")[0].split("#")[0].split("/").filter(Boolean);
        if (parts.length !== 1 || RESERVED[parts[0].toLowerCase()]) continue;
        return "/" + parts[0] + "/";
      }
      return null;
    }

    // Your own posts never count toward the cap, on any page.
    function isOwnPost(el) {
      if (!el || el.nodeType !== 1) return false;
      if (el.getAttribute("data-enough-own") === "1") return true;
      var own = ownProfilePath();
      if (!own) return false;
      var author = authorPath(el);
      if (!author || author.toLowerCase() !== own.toLowerCase()) return false;
      el.setAttribute("data-enough-own", "1");
      return true;
    }

    function onIntersect(entries) {
      if (capState.reached) return;
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        var ratio = typeof entry.intersectionRatio === "number" ? entry.intersectionRatio : 0;
        if (ratio < 0.5) continue;
        var el = entry.target;
        if (!el || !el.getAttribute) continue;
        if (el.classList && (el.classList.contains("enough-hidden") || el.classList.contains("enough-seen") || el.classList.contains("enough-keep") || el.classList.contains("enough-cap-hidden"))) continue;
        var key = el.getAttribute("data-enough-key");
        if (!key || seen.has(key) || alreadySeen.has(key)) continue;
        if (isOwnPost(el)) continue;
        seen.add(key);
        alreadySeen.add(key);
        el.setAttribute("data-enough-counted", "1");
        emit({ type: "postViewed", permalink: key });
      }
    }

    function wrapHistory(history, name, notify) {
      if (!history || typeof history[name] !== "function") return;
      var original = history[name];
      history[name] = function () {
        var result = original.apply(history, arguments);
        notify();
        return result;
      };
    }

    function hookHistory() {
      var view = doc && doc.defaultView;
      if (!view || historyHooked) return;
      historyHooked = true;
      var notify = function () {
        if (redirectExploreRoot()) return;
        setRoute();
        renderNotice();
        markTabBar();
        if (routeHidesArticles()) hideRouteArticles(doc);
        emit({ type: "route", path: currentPath() });
      };
      wrapHistory(view.history, "pushState", notify);
      wrapHistory(view.history, "replaceState", notify);
      if (typeof view.addEventListener === "function") view.addEventListener("popstate", notify);
      emit({ type: "route", path: currentPath() });
    }

    function ensureFollowing() {
      // Only a home URL with a query (for example ?variant=following) needs a redirect.
      if (didRedirect || !followingURL || followingURL.indexOf("?") === -1) return;
      var view = doc && doc.defaultView;
      if (!view || !view.location || !view.location.replace) return;
      var path = view.location.pathname || "/";
      if (path !== "/") return;
      var search = view.location.search || "";
      if (search.indexOf("variant=following") !== -1) return;
      didRedirect = true;
      view.location.replace(followingURL);
    }

    function isExploreRoot() {
      var view = doc && doc.defaultView;
      if (!view || !view.location) return false;
      var parts = String(view.location.pathname || "/").split("/").filter(Boolean);
      return parts.length === 1 && parts[0].toLowerCase() === "explore";
    }

    // Try the site's own router first so the tab switch is instant. Fall back to a page load.
    function goToSearch(replace) {
      var view = doc && doc.defaultView;
      if (!view || !view.location) return;
      var full = "https://www.instagram.com" + SEARCH_PATH;
      try {
        pushRoute(view, SEARCH_PATH, replace);
      } catch (err) {
        view.location.assign(full);
        return;
      }
      if (view.setTimeout) {
        view.setTimeout(function () {
          if (!doc.querySelector("input[type='search']") && classifyPath(currentPath()) === "search") {
            view.location.replace(full);
          }
        }, 2000);
      }
    }

    function redirectExploreRoot() {
      if (!toggles.hideExplore || !isExploreRoot()) return false;
      goToSearch(true);
      return true;
    }

    function onClickCapture(event) {
      var target = event && event.target;
      if (!target || !target.closest) return;
      var link = target.closest("[data-enough-search='1']");
      if (!link || !toggles.hideExplore) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.stopImmediatePropagation) event.stopImmediatePropagation();
      if (classifyPath(currentPath()) === "search") return;
      goToSearch(false);
    }

    var engine = {
      start: function () {
        if (started || !doc) return engine;
        started = true;
        installCSS();
        var IO = options.IntersectionObserver;
        if (!IO && doc.defaultView) IO = doc.defaultView.IntersectionObserver;
        if (typeof IO === "function") {
          try {
            io = new IO(onIntersect, { threshold: [0.5] });
          } catch (err) {
            io = null;
          }
        }
        applyAll();
        checkReady();
        rememberProfile();
        markTabBar();
        ensureFollowing();
        redirectExploreRoot();
        if (typeof doc.addEventListener === "function") doc.addEventListener("click", onClickCapture, true);
        var MO = options.MutationObserver;
        if (!MO && doc.defaultView) MO = doc.defaultView.MutationObserver;
        if (typeof MO === "function" && doc.documentElement) {
          mo = new MO(function (mutations) {
            for (var i = 0; i < mutations.length; i++) {
              var added = mutations[i].addedNodes || [];
              for (var n = 0; n < added.length; n++) queueScan(added[n]);
            }
          });
          mo.observe(doc.documentElement, { childList: true, subtree: true });
        }
        hookHistory();
        return engine;
      },
      stop: function () {
        if (doc && typeof doc.removeEventListener === "function") doc.removeEventListener("click", onClickCapture, true);
        if (mo) mo.disconnect();
        if (io) io.disconnect();
        mo = null;
        io = null;
        started = false;
      },
      reconfigure: function (boot) {
        boot = boot || {};
        if (boot.config) config = boot.config;
        if (boot.toggles) toggles = normalizeToggles(boot.toggles);
        if (typeof boot.css === "string" && boot.css) {
          cssText = boot.css;
          installCSS();
        }
        if (boot.seen) {
          for (var i = 0; i < boot.seen.length; i++) alreadySeen.add(boot.seen[i]);
        }
        if (boot.homeURL) followingURL = boot.homeURL;
        if (typeof boot.hideSponsored === "boolean") hideSponsored = boot.hideSponsored;
        applyAll();
      },
      setCapState: function (reached, resetText) {
        capState = { reached: !!reached, resetText: typeof resetText === "string" ? resetText : "" };
        renderNotice();
      },
      applyToggles: function (next) {
        toggles = normalizeToggles(next);
        applyAll();
      },
      openProfile: function () {
        var store = storage();
        var saved = null;
        try { saved = store ? store.getItem(PROFILE_KEY) : null; } catch (err) { saved = null; }
        if (saved && /^\/[A-Za-z0-9._]{1,30}\/$/.test(saved)) {
          var link = doc.querySelector("a[href='" + saved + "']");
          if (link) link.click();
          else spaNavigate(saved);
          return true;
        }
        var anchors = queryAll(doc, "a[href]");
        var candidate = null;
        for (var i = 0; i < anchors.length; i++) {
          var href = anchors[i].getAttribute("href") || "";
          if (href.charAt(0) !== "/") continue;
          var parts = href.split("?")[0].split("#")[0].split("/").filter(Boolean);
          if (parts.length !== 1) continue;
          if (RESERVED[parts[0].toLowerCase()]) continue;
          candidate = anchors[i];
        }
        if (!candidate) return false;
        candidate.click();
        return true;
      },
      navigate: function (path) {
        if (typeof path !== "string" || !/^\/[A-Za-z0-9._\/-]*$/.test(path)) return false;
        if (path === SEARCH_PATH) {
          if (classifyPath(currentPath()) !== "search") goToSearch(false);
          return true;
        }
        if (currentPath().split("?")[0] === path) return true;
        spaNavigate(path);
        return true;
      },
      openDirect: function () { spaNavigate("/direct/inbox/"); return true; },
      openHome: function () { spaNavigate("/"); return true; },
      openSearch: function () {
        if (classifyPath(currentPath()) !== "search") goToSearch(false);
        return true;
      },
      classifyPath: classifyPath
    };

    return engine;
  }

  return {
    createEngine: createEngine,
    classifyPath: classifyPath,
    permalinkOf: permalinkOf
  };
});
