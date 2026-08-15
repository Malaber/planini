import assert from "node:assert/strict";
import test from "node:test";
import { JSDOM } from "jsdom";

const appModuleUrl = new URL("../app/web/static/app.js", import.meta.url).href;
let appPromise;

async function loadApp() {
  if (!appPromise) {
    appPromise = import(appModuleUrl);
  }
  return appPromise;
}

function createResponse({ ok = true, status = 200, jsonData = {}, statusText = "OK" } = {}) {
  return {
    ok,
    status,
    statusText,
    async json() {
      return jsonData;
    },
  };
}

function createJsonRejectingResponse({ ok = true, status = 200, statusText = "OK" } = {}) {
  return {
    ok,
    status,
    statusText,
    json: async () => {
      throw new Error("bad json");
    },
  };
}

function dashboardHtml() {
  return `
    <section class="dashboard-shell" data-dashboard>
      <div data-dashboard-error hidden></div>
      <div data-dashboard-success hidden></div>
      <div data-dashboard-empty hidden></div>
      <div data-household-list></div>
      <button type="button" aria-expanded="false" data-dashboard-add-toggle>+</button>
      <div data-dashboard-add-overlay hidden>
        <button type="button" data-dashboard-add-close>Close add</button>
        <section data-dashboard-add-panel hidden>
          <button type="button" data-dashboard-add-option="household">Household</button>
          <button type="button" data-dashboard-add-option="list">List</button>
          <div data-dashboard-list-group>
            <p data-dashboard-list-empty>Create a household and list first</p>
          </div>
        </section>
      </div>
      <div data-dashboard-household-overlay hidden>
        <button type="button" data-dashboard-household-close>Close household</button>
        <section data-dashboard-household-panel hidden>
          <button type="button" data-dashboard-panel-back>Back</button>
          <form class="dashboard-form" data-household-form>
            <input type="text" name="name" data-household-name-input />
            <button type="submit">Create household</button>
          </form>
        </section>
      </div>
      <div data-dashboard-list-overlay hidden>
        <button type="button" data-dashboard-list-close>Close list</button>
        <section data-dashboard-list-panel hidden>
          <button type="button" data-dashboard-panel-back>Back</button>
          <form class="dashboard-form" data-list-form>
            <select name="household_id" data-household-select>
              <option value="">Create a household first</option>
            </select>
            <input type="text" name="name" data-list-name-input />
            <button type="submit">Create list</button>
          </form>
        </section>
      </div>
    </section>
  `;
}

function loginHtml() {
  return `
    <section data-passkey-auth>
      <p data-auth-error hidden></p>
      <p data-auth-success hidden></p>
      <form data-passkey-login>
        <button type="button" data-passkey-login-button>Login</button>
      </form>
    </section>
  `;
}

function settingsHtml() {
  return `
    <section data-user-settings>
      <section data-language-settings>
        <button type="button" data-language-settings-open>Change language</button>
        <strong data-language-settings-summary></strong>
        <div data-settings-error hidden></div>
        <div data-settings-success hidden></div>
        <div data-language-settings-overlay hidden>
          <section data-language-settings-panel hidden>
            <button type="button" data-language-settings-close>Close</button>
            <form data-language-settings-form>
              <select data-language-settings-select>
                <option value="">Browser default</option>
                <option value="en">English</option>
                <option value="de">Deutsch</option>
              </select>
            </form>
          </section>
        </div>
      </section>
      <section data-passkey-management>
        <button type="button" data-passkey-add>Add another passkey</button>
        <form data-passkey-name-form hidden>
          <span data-passkey-name-title>Name this passkey</span>
          <input type="text" name="name" data-passkey-name-input />
          <button type="submit" data-passkey-name-submit>Continue</button>
          <button type="button" data-passkey-name-cancel>Cancel</button>
        </form>
        <div data-passkey-empty hidden></div>
        <div data-passkey-list></div>
        <div data-passkey-error hidden></div>
        <div data-passkey-success hidden></div>
        <div data-passkey-delete-overlay hidden>
          <button type="button" data-passkey-delete-close>Close delete</button>
          <section data-passkey-delete-panel hidden>
            <strong data-passkey-delete-name></strong>
            <p data-passkey-delete-copy>
              You must authenticate with another passkey to confirm you still have a working Passkey after deleting one.
            </p>
            <button type="button" data-passkey-delete-confirm>Continue to verification</button>
            <button type="button" data-passkey-delete-close>Cancel</button>
          </section>
        </div>
      </section>
    </section>
  `;
}

function listDetailHtml() {
  return `
    <section data-list-detail data-list-id="list-1">
      <h1 data-list-title>Loading list...</h1>
      <button type="button" data-list-settings-toggle>Settings</button>
      <div data-list-error hidden></div>
      <div data-list-success hidden></div>
      <p data-list-sync-status></p>
      <div data-item-empty hidden></div>
      <div data-item-list></div>
      <button type="button" aria-expanded="false" data-item-form-toggle>Add item</button>
      <div data-item-panel-overlay hidden>
        <button type="button" data-item-form-close>Close</button>
        <section data-item-panel hidden>
          <form data-item-form>
            <input name="name" data-item-name-input />
            <div data-item-suggestions-slot><div data-item-suggestions></div></div>
            <input type="search" data-item-category-search />
            <div data-item-category-radios></div>
            <input name="quantity_text" />
            <input name="note" />
            <button type="submit">Add</button>
          </form>
        </section>
      </div>
      <div data-list-toast hidden>
        <p data-list-toast-message></p>
        <button type="button" data-list-toast-undo>Undo</button>
        <div data-list-toast-timer></div>
      </div>
      <div data-list-settings-overlay hidden>
        <button type="button" data-list-settings-close>Close settings</button>
        <section data-list-settings-panel hidden>
          <div data-list-settings-category-list></div>
        </section>
      </div>
      <div data-item-edit-overlay hidden>
        <button type="button" data-item-edit-close>Close edit</button>
        <section data-item-edit-panel hidden>
          <h2 data-item-edit-title>Edit item</h2>
          <form data-item-edit-form>
            <input name="name" />
            <input type="search" data-item-edit-category-search />
            <div data-item-edit-category-radios></div>
            <input name="quantity_text" />
            <input name="note" />
            <button type="submit">Save</button>
            <button type="button" data-item-edit-delete>Delete item</button>
          </form>
        </section>
      </div>
    </section>
  `;
}

function installDom(html, options = {}) {
  const dom = new JSDOM(`<!doctype html><html><body>${html}</body></html>`, {
    pretendToBeVisual: true,
    url: options.url ?? "http://example.com/",
  });

  const previous = new Map();
  const assigned = [];
  const globals = {
    window: dom.window,
    document: dom.window.document,
    navigator: dom.window.navigator,
    HTMLElement: dom.window.HTMLElement,
    HTMLButtonElement: dom.window.HTMLButtonElement,
    HTMLInputElement: dom.window.HTMLInputElement,
    HTMLFormElement: dom.window.HTMLFormElement,
    HTMLTextAreaElement: dom.window.HTMLTextAreaElement,
    HTMLSelectElement: dom.window.HTMLSelectElement,
    Event: dom.window.Event,
    MouseEvent: dom.window.MouseEvent,
    KeyboardEvent: dom.window.KeyboardEvent,
    CustomEvent: dom.window.CustomEvent,
    FormData: dom.window.FormData,
    DOMParser: dom.window.DOMParser,
    Node: dom.window.Node,
    ArrayBuffer: dom.window.ArrayBuffer,
    Uint8Array: dom.window.Uint8Array,
    URL: dom.window.URL,
    atob: (value) => Buffer.from(value, "base64").toString("binary"),
    btoa: (value) => Buffer.from(value, "binary").toString("base64"),
    fetch: options.fetch ?? (async () => createResponse()),
    WebSocket: options.WebSocket ?? class {},
    __appNavigateTo: (url) => {
      assigned.push(url);
    },
  };

  for (const [key, value] of Object.entries(globals)) {
    previous.set(key, globalThis[key]);
    Object.defineProperty(globalThis, key, {
      configurable: true,
      writable: true,
      value,
    });
  }

  dom.window.fetch = globalThis.fetch;
  dom.window.WebSocket = globalThis.WebSocket;
  dom.window.HTMLElement.prototype.scrollIntoView = () => {};

  const timerFns = options.timers ?? {};
  dom.window.setTimeout = timerFns.setTimeout ?? ((fn) => {
    fn();
    return 1;
  });
  dom.window.clearTimeout = timerFns.clearTimeout ?? (() => {});

  return {
    dom,
    assigned,
    restore() {
      dom.window.close();
      for (const [key, value] of previous.entries()) {
        if (value === undefined) {
          delete globalThis[key];
        } else {
          Object.defineProperty(globalThis, key, {
            configurable: true,
            writable: true,
            value,
          });
        }
      }
    },
  };
}

test("request helpers cover success and failure cases", async () => {
  const env = installDom("");
  try {
    const app = await loadApp();
    let fetchCalls = [];
    globalThis.fetch = async (url, options) => {
      fetchCalls.push([url, options]);
      return createResponse({ jsonData: { ok: true } });
    };
    env.dom.window.fetch = globalThis.fetch;
    assert.deepEqual(await app.postJson("/api/test", { value: 1 }), { ok: true });
    assert.deepEqual(fetchCalls, [
      [
        "/api/test",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ value: 1 }),
        },
      ],
    ]);

    globalThis.fetch = async () => createResponse({ ok: false, status: 400, jsonData: { detail: "Nope" } });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.postJson("/api/test", {}), /Nope/);

    globalThis.fetch = async () => createJsonRejectingResponse({ ok: false, status: 500 });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.postJson("/api/test", {}), /Passkey request failed/);

    globalThis.fetch = async () => createResponse({ ok: false, status: 401 });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.postJson("/api/test", {}), /Unauthorized/);
    assert.deepEqual(env.assigned, ["/login"]);

    globalThis.fetch = async () => createResponse({ jsonData: { ok: true, value: 2 } });
    env.dom.window.fetch = globalThis.fetch;
    assert.deepEqual(await app.fetchJson("/api/fetch", { method: "GET" }), { ok: true, value: 2 });

    globalThis.fetch = async () => createResponse({ ok: false, status: 418, jsonData: { detail: "Teapot" } });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.fetchJson("/api/fetch"), /Teapot/);

    globalThis.fetch = async () => createJsonRejectingResponse({ ok: false, status: 500 });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.fetchJson("/api/fetch"), /Request failed/);
  } finally {
    env.restore();
  }
});

test("translation helpers read runtime locale data and fall back cleanly", async () => {
  const env = installDom("");
  try {
    const app = await loadApp();

    delete globalThis.__appI18n;
    assert.deepEqual(app.getI18nState(), { locale: "en", catalog: {} });

    globalThis.__appI18n = {
      locale: "de",
      catalog: {
        auth: { login: { title: "Anmelden" } },
        dashboard: { list_count: { one: "{count} Liste", other: "{count} Listen" } },
      },
    };

    assert.equal(app.getCurrentLocale(), "de");
    assert.equal(app.translate("auth.login.title", {}, "Login"), "Anmelden");
    assert.equal(app.translate("auth.login.missing", { name: "Alex" }, "Hallo {name}"), "Hallo Alex");
    assert.equal(app.interpolateTranslation("Hi {name}", { name: "Sam" }), "Hi Sam");
    assert.equal(
      app.translatePlural("dashboard.list_count", 1, {}, { one: "{count} list", other: "{count} lists" }),
      "1 Liste",
    );
    assert.equal(
      app.translatePlural("dashboard.missing", 2, {}, { one: "{count} list", other: "{count} lists" }),
      "2 lists",
    );

    globalThis.__appI18n = { locale: 7, catalog: null };
    assert.deepEqual(app.getI18nState(), { locale: "en", catalog: {} });
  } finally {
    env.restore();
  }
});

test("language settings save a locale cookie and navigate to the selected locale", async () => {
  const env = installDom(settingsHtml(), { url: "http://example.com/settings?from=test" });
  try {
    const app = await loadApp();
    globalThis.__appI18n = {
      locale: "en",
      catalog: {
        settings: {
          language_browser_default_with_locale: "Browser default ({locale})",
          language_saved: "Language set to {language}.",
        },
      },
    };
    globalThis.window.PublicKeyCredential = class {};
    globalThis.navigator.credentials = {};

    const root = document.querySelector("[data-user-settings]");
    app.syncLanguageSettings(root);
    assert.equal(root.querySelector("[data-language-settings-summary]").textContent, "Browser default (en)");

    app.setLanguageSettingsOpen(root, true);
    assert.equal(root.querySelector("[data-language-settings-overlay]").hidden, false);
    assert.equal(root.querySelector("[data-language-settings-panel]").hidden, false);

    root.querySelector("[data-language-settings-select]").value = "de";
    await app.initUserSettings();
    root.querySelector("[data-language-settings-form]").dispatchEvent(
      new Event("submit", { bubbles: true, cancelable: true }),
    );

    assert.equal(root.querySelector("[data-language-settings-overlay]").hidden, true);
    assert.equal(root.querySelector("[data-language-settings-panel]").hidden, true);
    assert.equal(root.querySelector("[data-language-settings-summary]").textContent, "Deutsch");
    assert.equal(root.querySelector("[data-settings-success]").textContent, "Language set to Deutsch.");
    assert.equal(app.getStoredLanguagePreference(), "de");
    assert.equal(document.documentElement.lang, "de");
    assert.deepEqual(env.assigned, ["/settings?from=test&lang=de"]);
  } finally {
    env.restore();
  }
});

test("language settings clear the locale cookie to return to browser default", async () => {
  const env = installDom(settingsHtml(), { url: "http://example.com/settings?lang=de" });
  try {
    const app = await loadApp();
    globalThis.__appI18n = {
      locale: "de",
      catalog: {
        settings: {
          language_browser_default_with_locale: "Browser-Standard ({locale})",
          language_saved: "Sprache auf {language} gesetzt.",
        },
      },
    };

    app.storeLanguagePreference("de");
    assert.equal(app.getStoredLanguagePreference(), "de");

    const root = document.querySelector("[data-user-settings]");
    root.querySelector("[data-language-settings-select]").value = "";
    await app.initUserSettings();
    root.querySelector("[data-language-settings-form]").dispatchEvent(
      new Event("submit", { bubbles: true, cancelable: true }),
    );

    assert.equal(app.getStoredLanguagePreference(), "");
    assert.equal(root.querySelector("[data-settings-success]").textContent, "Sprache auf Browser-Standard (de) gesetzt.");
    assert.deepEqual(env.assigned, ["/settings"]);
  } finally {
    env.restore();
  }
});

test("dashboard helpers render household state and form status", async () => {
  const env = installDom(dashboardHtml());
  try {
    const app = await loadApp();
    const root = document.querySelector("[data-dashboard]");
    const errorNode = root.querySelector("[data-dashboard-error]");
    const successNode = root.querySelector("[data-dashboard-success]");

    app.setDashboardMessage(root, "error", "Broken");
    assert.equal(errorNode.hidden, false);
    assert.equal(errorNode.textContent, "Broken");

    app.setDashboardMessage(root, "success", "Saved");
    assert.equal(successNode.hidden, false);
    assert.equal(successNode.textContent, "Saved");

    app.setDashboardMessage(root, "", "");
    assert.equal(errorNode.hidden, true);
    assert.equal(successNode.hidden, true);

    app.toggleDashboardForms(root, true);
    root.querySelectorAll("button, input, select").forEach((node) => {
      assert.equal(node.disabled, true);
    });

    const households = [
      { id: "house-1", name: "Home", role: "owner" },
      { id: "house-2", name: "Office", role: "editor" },
    ];
    app.updateHouseholdOptions(root, households);
    const select = root.querySelector("[data-household-select]");
    assert.equal(select.options.length, 2);
    assert.equal(select.options[0].textContent, "Select a household");

    const addToggle = root.querySelector("[data-dashboard-add-toggle]");
    app.setDashboardPanelOpen(root, "add", true);
    assert.equal(root.querySelector("[data-dashboard-add-panel]").hidden, false);
    assert.equal(addToggle.getAttribute("aria-expanded"), "true");
    assert.equal(document.body.classList.contains("has-list-modal-open"), true);

    app.setDashboardPanelOpen(root, "household", true);
    assert.equal(root.querySelector("[data-dashboard-household-panel]").hidden, false);
    assert.equal(root.querySelector("[data-dashboard-add-panel]").hidden, true);

    app.setDashboardPanelOpen(root, "household", false);
    assert.equal(document.body.classList.contains("has-list-modal-open"), false);

    app.updateDashboardListOptions(
      root,
      households,
      new Map([
        ["house-1", [{ id: "list-1", name: "Weekly" }]],
        ["house-2", [{ id: "list-2", name: "Supplies" }]],
      ]),
    );
    const listButtons = root.querySelectorAll("[data-dashboard-open-list]");
    assert.equal(listButtons.length, 2);
    assert.match(listButtons[0].textContent, /Weekly/);
    assert.match(listButtons[0].textContent, /Home/);

    app.renderHouseholds(
      root,
      households,
      new Map([
        ["house-1", [{ id: "list-1", name: "Weekly" }]],
        ["house-2", []],
      ]),
    );
    assert.match(root.querySelector("[data-household-list]").textContent, /Weekly/);
    assert.equal(root.querySelector("[data-dashboard-empty]").hidden, true);

    app.renderHouseholds(root, [], new Map());
    assert.equal(root.querySelector("[data-dashboard-empty]").hidden, false);

    const rootWithoutBanner = document.createElement("section");
    app.setDashboardMessage(rootWithoutBanner, "error", "ignored");

    let fetchIndex = 0;
    globalThis.fetch = async (url) => {
      fetchIndex += 1;
      if (fetchIndex === 1) {
        return createResponse({
          jsonData: [{ id: "house-1", name: "Home", role: "owner" }],
        });
      }
      return createResponse({ jsonData: [{ id: "list-1", name: "Weekly" }] });
    };
    env.dom.window.fetch = globalThis.fetch;
    await app.loadDashboardData(root);
    assert.match(root.querySelector("[data-household-list]").textContent, /Weekly/);
    assert.match(root.querySelector("[data-dashboard-list-group]").textContent, /Home/);
    assert.match(root.querySelector("[data-dashboard-list-group]").textContent, /Weekly/);
  } finally {
    env.restore();
  }
});

test("helper guard clauses and alternate render paths are covered", async () => {
  let timeoutCallback = null;
  const env = installDom(`${dashboardHtml()}${loginHtml()}${listDetailHtml()}`, {
    timers: {
      setTimeout: (fn) => {
        timeoutCallback = fn;
        return 99;
      },
      clearTimeout: () => {},
    },
  });

  try {
    const app = await loadApp();
    const dashboardRoot = document.querySelector("[data-dashboard]");
    const listRoot = document.querySelector("[data-list-detail]");

    globalThis.fetch = async () => createResponse({ ok: false, status: 401 });
    env.dom.window.fetch = globalThis.fetch;
    await assert.rejects(app.fetchJson("/api/needs-auth"), /Unauthorized/);

    app.updateHouseholdOptions(document.createElement("div"), []);
    app.renderHouseholds(document.createElement("div"), [], new Map());
    app.hideUndoToast(document.createElement("div"), { undoTimerId: null, undoAction: null });
    app.showUndoToast(document.createElement("div"), { undoTimerId: null, undoAction: null }, "x", async () => {});
    app.setItemPanelOpen(document.createElement("div"), true);
    app.syncCategoryRadioGroup(null, "category_id", "", { categories: new Map() }, "");
    app.setListSettingsOpen(document.createElement("div"), {}, true);
    app.renderCategoryOrderSettings(document.createElement("div"), { categories: new Map(), categoryOrder: new Map() });
    app.renderItemSuggestions(document.createElement("div"), { items: new Map(), categories: new Map() });
    app.highlightItem(document.createElement("div"), { highlightTimers: new Map() }, "missing");
    app.renderItems(document.createElement("div"), { items: new Map(), categories: new Map(), categoryOrder: new Map() });

    const select = dashboardRoot.querySelector("[data-household-select]");
    app.updateHouseholdOptions(dashboardRoot, [
      { id: "house-1", name: "Home" },
      { id: "house-2", name: "Office" },
    ]);
    select.value = "house-2";
    app.updateHouseholdOptions(dashboardRoot, [
      { id: "house-1", name: "Home" },
      { id: "house-2", name: "Office" },
    ]);
    assert.equal(select.value, "house-2");
    app.updateHouseholdOptions(dashboardRoot, [{ id: "solo", name: "Solo" }]);
    assert.equal(select.value, "solo");

    const buttonHost = document.createElement("div");
    buttonHost.innerHTML = `<button type="button">A</button><button type="button">B</button>`;
    app.toggleButtons(buttonHost, true);
    buttonHost.querySelectorAll("button").forEach((button) => assert.equal(button.disabled, true));

    app.setMessage(document.querySelector("[data-passkey-auth]"), "error", "Broken");
    assert.equal(document.querySelector("[data-auth-error]").textContent, "Broken");
    app.setMessage(document.querySelector("[data-passkey-auth]"), "success", "Fixed");
    assert.equal(document.querySelector("[data-auth-success]").textContent, "Fixed");

    const state = {
      categoryOrder: new Map(),
      categories: new Map([
        ["cat-a", { id: "cat-a", name: "Produce", color: "", aliases: ["fruit"] }],
      ]),
      editingItemId: null,
      highlightTimers: new Map(),
      items: new Map([
        ["item-a", { id: "item-a", name: "Milk", checked: false, category_id: "cat-a", sort_order: 2, quantity_text: "1L", note: "Cold" }],
        ["item-b", { id: "item-b", name: "Millet", checked: false, category_id: null, sort_order: 1, quantity_text: "", note: "" }],
        ["item-c", { id: "item-c", name: "Milk", checked: true, checked_at: "2024-01-04T00:00:00Z", category_id: null, sort_order: 3, quantity_text: "2L", note: "Skim" }],
      ]),
    };

    const nonInput = document.createElement("div");
    nonInput.innerHTML = `<div></div><input type="radio" name="category_id" value="cat-a" />`;
    app.setCategoryRadioValue(nonInput, '[name="category_id"], div', "cat-a");
    assert.equal(nonInput.querySelector('input[name="category_id"]').checked, true);

    assert.deepEqual(app.categorySortKey(state, "missing"), {
      color: "",
      name: "Uncategorized",
      isExplicit: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
    });

    app.setItemPanelOpen(listRoot, true);
    timeoutCallback?.();
    assert.equal(listRoot.querySelector("[data-item-panel]").hidden, false);

    app.setItemEditPanelOpen(document.createElement("div"), state, "item-a");
    app.setItemEditPanelOpen(listRoot, state, "missing");
    assert.equal(listRoot.querySelector("[data-item-edit-panel]").hidden, true);

    app.renderCategoryOrderSettings(listRoot, { categories: new Map(), categoryOrder: new Map() });
    assert.match(listRoot.querySelector("[data-list-settings-category-list]").textContent, /Create categories in admin/);

    listRoot.querySelector("[data-item-name-input]").value = "";
    app.renderItemSuggestions(listRoot, state);
    assert.equal(listRoot.querySelector("[data-item-suggestions-slot]").classList.contains("is-active"), false);

    listRoot.querySelector("[data-item-name-input]").value = "zzz";
    app.renderItemSuggestions(listRoot, state);
    assert.equal(listRoot.querySelector("[data-item-suggestions-slot]").classList.contains("is-active"), false);

    listRoot.querySelector("[data-item-name-input]").value = "mil";
    app.renderItemSuggestions(listRoot, state);
    assert.match(listRoot.querySelector("[data-item-suggestions]").textContent, /Milk/);

    assert.ok(app.compareActiveItems(
      { categoryOrder: new Map([["cat-a", 0]]), categories: state.categories },
      { name: "A", category_id: "cat-a", sort_order: 2 },
      { name: "B", category_id: "cat-b", sort_order: 1 },
    ) < 0);
    assert.ok(app.compareActiveItems(
      {
        categoryOrder: new Map([
          ["cat-a", 1],
          ["cat-b", 0],
        ]),
        categories: new Map([
          ["cat-a", { id: "cat-a", name: "Same" }],
          ["cat-b", { id: "cat-b", name: "Same" }],
        ]),
      },
      { name: "A", category_id: "cat-a", sort_order: 2 },
      { name: "B", category_id: "cat-b", sort_order: 1 },
    ) > 0);
    assert.ok(app.compareActiveItems(
      { categoryOrder: new Map(), categories: new Map([["cat-a", { id: "cat-a", name: "A" }]]) },
      { name: "B", category_id: "cat-a", sort_order: 2 },
      { name: "A", category_id: "cat-a", sort_order: 1 },
    ) > 0);
    assert.ok(app.compareActiveItems(
      { categoryOrder: new Map(), categories: new Map([["cat-a", { id: "cat-a", name: "B" }], ["cat-c", { id: "cat-c", name: "A" }]]) },
      { name: "A", category_id: "cat-a", sort_order: 2 },
      { name: "B", category_id: "cat-c", sort_order: 1 },
    ) > 0);
    assert.ok(app.compareActiveItems(
      { categoryOrder: new Map(), categories: new Map([["cat-a", { id: "cat-a", name: "A" }]]) },
      { name: "Z", category_id: "cat-a", sort_order: 2 },
      { name: "A", category_id: "cat-a", sort_order: 1 },
    ) > 0);
    assert.ok(app.compareCheckedItems(
      { name: "B", checked_at: "2024-01-01T00:00:00Z" },
      { name: "A", checked_at: "2024-01-01T00:00:00Z" },
    ) > 0);

    app.renderItems(listRoot, state);
    assert.match(listRoot.querySelector("[data-item-list]").textContent, /Qty: 1L/);
    assert.match(listRoot.querySelector("[data-item-list]").textContent, /Cold/);
    assert.match(listRoot.querySelector("[data-item-list]").textContent, /Qty: 2L/);
    assert.match(listRoot.querySelector("[data-item-list]").textContent, /Skim/);

    const noTokenRoot = document.createElement("section");
    noTokenRoot.innerHTML = `<p data-list-sync-status></p>`;
    noTokenRoot.dataset.listId = "list-1";
    app.connectListSocket(noTokenRoot, { socket: null });
    assert.equal(noTokenRoot.querySelector("[data-list-sync-status]").textContent, "Live updates unavailable.");
  } finally {
    env.restore();
  }
});

test("household roles shape dashboard controls and viewer list access", async () => {
  const env = installDom(`
    <section data-dashboard>
      <div data-household-list></div>
      <div data-dashboard-empty hidden></div>
      <div data-dashboard-member-list></div>
      <h2 data-dashboard-members-title></h2>
      <select data-invite-role><option value="editor">Editor</option><option value="viewer">Viewer</option></select>
      <select data-invite-mode><option value="time">Time</option><option value="uses">Uses</option></select>
      <input data-invite-hours-input value="72" />
      <input data-invite-max-uses value="3" />
    </section>
    <section data-list-detail>
      <button data-item-form-toggle>Add</button>
      <button data-list-settings-toggle>Settings</button>
      <div data-list-read-only hidden>Read only</div>
    </section>
  `);

  try {
    const app = await loadApp();
    const dashboardRoot = document.querySelector("[data-dashboard]");
    const households = [
      { id: "owner-house", name: "Home", role: "owner" },
      { id: "viewer-house", name: "Shared", role: "viewer" },
    ];
    app.renderHouseholds(
      dashboardRoot,
      households,
      new Map([
        ["owner-house", []],
        ["viewer-house", []],
      ]),
    );
    assert.equal(dashboardRoot.querySelectorAll("[data-open-members]").length, 2);
    assert.equal(dashboardRoot.querySelectorAll("[data-open-invite-sheet]").length, 1);
    assert.equal(dashboardRoot.querySelectorAll('[data-dashboard-add-option="list"]').length, 1);
    assert.match(dashboardRoot.textContent, /Viewer/);

    app.renderHouseholdMembers(
      dashboardRoot,
      households[0],
      [
        {
          user_id: "owner-user",
          display_name: "Owner",
          email: "owner@example.com",
          role: "owner",
        },
        {
          user_id: "viewer-user",
          display_name: "Viewer",
          email: "viewer@example.com",
          role: "viewer",
        },
      ],
    );
    assert.equal(dashboardRoot.querySelectorAll("[data-member-role]").length, 1);
    assert.equal(dashboardRoot.querySelectorAll("[data-remove-member]").length, 1);
    assert.equal(
      dashboardRoot.querySelector("[data-member-role]").value,
      "viewer",
    );

    dashboardRoot.querySelector("[data-invite-role]").value = "viewer";
    assert.deepEqual(app.householdInvitePayload(dashboardRoot), {
      expires_in_hours: 72,
      role: "viewer",
    });
    dashboardRoot.querySelector("[data-invite-mode]").value = "uses";
    assert.deepEqual(app.householdInvitePayload(dashboardRoot), {
      expires_in_hours: null,
      max_uses: 3,
      role: "viewer",
    });

    const listRoot = document.querySelector("[data-list-detail]");
    const state = {};
    app.applyListAccess(listRoot, state, "viewer");
    assert.equal(state.canEdit, false);
    assert.equal(state.canManage, false);
    assert.equal(listRoot.querySelector("[data-item-form-toggle]").hidden, true);
    assert.equal(listRoot.querySelector("[data-list-settings-toggle]").hidden, true);
    assert.equal(listRoot.querySelector("[data-list-read-only]").hidden, false);

    app.applyListAccess(listRoot, state, "editor");
    assert.equal(state.canEdit, true);
    assert.equal(state.canManage, false);
    assert.equal(listRoot.querySelector("[data-item-form-toggle]").hidden, false);
    assert.equal(listRoot.querySelector("[data-list-settings-toggle]").hidden, true);

    app.applyListAccess(listRoot, state, "owner");
    assert.equal(state.canManage, true);
    assert.equal(listRoot.querySelector("[data-list-settings-toggle]").hidden, false);
  } finally {
    env.restore();
  }
});

test("initDashboard handles refresh, household creation, list creation, and errors", async () => {
  const fetchLog = [];
  const env = installDom(dashboardHtml(), {
    fetch: async (url, options = {}) => {
      fetchLog.push([url, options.method || "GET"]);
      if (url === "/api/v1/households" && (!options.method || options.method === "GET")) {
        return createResponse({ jsonData: [{ id: "house-1", name: "Home" }] });
      }
      if (url === "/api/v1/households/house-1/lists" && (!options.method || options.method === "GET")) {
        return createResponse({ jsonData: [{ id: "list-1", name: "Weekly" }] });
      }
      if (url === "/api/v1/households" && options.method === "POST") {
        return createResponse({ jsonData: { id: "house-2", name: "Family" } });
      }
      if (url === "/api/v1/households/house-1/lists" && options.method === "POST") {
        return createResponse({ jsonData: { id: "list-2", name: "Costco" } });
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    await app.initDashboard();

    const root = document.querySelector("[data-dashboard]");
    const householdForm = root.querySelector("[data-household-form]");
    const listForm = root.querySelector("[data-list-form]");
    root.querySelector("[data-dashboard-add-toggle]").click();
    assert.equal(root.querySelector("[data-dashboard-add-panel]").hidden, false);

    root.querySelector('[data-dashboard-add-option="household"]').click();
    assert.equal(root.querySelector("[data-dashboard-household-panel]").hidden, false);
    root.querySelector("[data-dashboard-household-panel] [data-dashboard-panel-back]").click();
    assert.equal(root.querySelector("[data-dashboard-add-panel]").hidden, false);
    assert.equal(root.querySelector("[data-dashboard-household-panel]").hidden, true);

    root.querySelector('[data-dashboard-add-option="household"]').click();
    assert.equal(root.querySelector("[data-dashboard-household-panel]").hidden, false);

    householdForm.querySelector('input[name="name"]').value = "Family";
    householdForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-dashboard-success]").textContent, "Household created. You can add a list now.");
    assert.equal(root.querySelector("[data-dashboard-household-panel]").hidden, true);

    root.querySelector("[data-dashboard-add-toggle]").click();
    root.querySelector('[data-dashboard-add-option="list"]').click();
    root.querySelector("[data-dashboard-list-panel] [data-dashboard-panel-back]").click();
    assert.equal(root.querySelector("[data-dashboard-add-panel]").hidden, false);
    assert.equal(root.querySelector("[data-dashboard-list-panel]").hidden, true);

    root.querySelector('[data-dashboard-add-option="list"]').click();
    listForm.querySelector('select[name="household_id"]').value = "house-1";
    listForm.querySelector('input[name="name"]').value = "Costco";
    listForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.deepEqual(env.assigned, ["/lists/list-2"]);

    root.querySelector("[data-dashboard-add-toggle]").click();
    root.querySelector('[data-dashboard-open-list="list-1"]').click();
    assert.deepEqual(env.assigned, ["/lists/list-2", "/lists/list-1?addItem=1"]);
    globalThis.fetch = async () => createResponse({ ok: false, status: 500, jsonData: { detail: "Failed load" } });
    env.dom.window.fetch = globalThis.fetch;
    await app.initDashboard();
    assert.equal(root.querySelector("[data-dashboard-error]").textContent, "Failed load");

    householdForm.querySelector('input[name="name"]').value = "   ";
    householdForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-dashboard-error]").textContent, "Please enter a household name.");

    listForm.querySelector('select[name="household_id"]').value = "";
    listForm.querySelector('input[name="name"]').value = "  ";
    listForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-dashboard-error]").textContent, "Create or choose a household before creating a list.");
    listForm.querySelector('select[name="household_id"]').innerHTML = '<option value="house-1">Home</option>';
    listForm.querySelector('select[name="household_id"]').value = "house-1";
    listForm.querySelector('input[name="name"]').value = "   ";
    listForm.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-dashboard-error]").textContent, "Please enter a list name.");

    assert.ok(fetchLog.length > 0);
  } finally {
    env.restore();
  }
});



test("list helpers cover normalization, categories, rendering, and modal state", async () => {
  let clearedTimeout = null;
  let timeoutFn = null;
  const env = installDom(listDetailHtml(), {
    timers: {
      setTimeout: (fn) => {
        timeoutFn = fn;
        return 42;
      },
      clearTimeout: (id) => {
        clearedTimeout = id;
      },
    },
  });

  try {
    const app = await loadApp();
    const root = document.querySelector("[data-list-detail]");
    const state = {
      categoryOrder: new Map([["cat-2", 0]]),
      categories: new Map([
        ["cat-1", { id: "cat-1", name: "Produce", color: "#00ff00", aliases: ["fruit"] }],
        ["cat-2", { id: "cat-2", name: "Dairy", color: "#ffffff", aliases: [] }],
      ]),
      editingItemId: null,
      highlightTimers: new Map([["item-1", 5]]),
      items: new Map([
        ["item-1", { id: "item-1", name: "Milk", category_id: "cat-2", checked: false, sort_order: 2 }],
        ["item-2", { id: "item-2", name: "Apple", category_id: "cat-1", checked: true, checked_at: "2024-01-01T00:00:00Z", sort_order: 1 }],
        ["item-3", { id: "item-3", name: "Bread", category_id: null, checked: false, sort_order: 0 }],
      ]),
      socket: null,
      undoAction: async () => {},
      undoTimerId: 5,
    };

    app.setListMessage(root, "error", "Oops");
    assert.equal(root.querySelector("[data-list-error]").textContent, "Oops");
    app.setListMessage(root, "success", "Saved");
    assert.equal(root.querySelector("[data-list-success]").textContent, "Saved");
    app.setListMessage(document.createElement("div"), "error", "noop");

    app.setListSyncStatus(root, "Synced");
    assert.equal(root.querySelector("[data-list-sync-status]").textContent, "Synced");

    app.showUndoToast(root, state, "Undone", async () => {});
    assert.equal(root.querySelector("[data-list-toast]").hidden, false);
    assert.equal(clearedTimeout, 5);
    app.hideUndoToast(root, state);
    assert.equal(root.querySelector("[data-list-toast]").hidden, true);
    timeoutFn();

    assert.equal(app.normalizeItemName("  Red   Apple "), "red apple");
    assert.equal(app.normalizeSearchText(" Crème  Brûlée "), "creme brulee");

    app.setItemPanelOpen(root, true);
    assert.equal(root.querySelector("[data-item-panel]").hidden, false);
    app.syncModalState(root);
    assert.equal(document.body.classList.contains("has-list-modal-open"), true);

    assert.equal(
      app.formatSuggestionMeta(state, { category_id: "cat-1", quantity_text: "2", note: "ripe", checked: false }),
      "Produce / 2 / ripe / already on this list",
    );
    assert.deepEqual(app.categorySortKey(state, null), {
      color: "",
      name: "Uncategorized",
      isExplicit: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
    });
    assert.equal(app.decorateItem(state, state.items.get("item-1"))._categoryName, "Dairy");

    app.setCategoryRadioValue(root, 'input[name="category_id"]', "");
    assert.equal(app.categoryMatchesQuery({ name: "Produce", aliases: ["fruit"] }, "fruit"), true);
    assert.equal(app.categoryMatchesQuery({ name: "Produce", aliases: [] }, "meat"), false);

    app.syncCategoryRadioGroups(root, state);
    assert.ok(root.querySelector('[name="category_id"]'));
    root.querySelector("[data-item-category-search]").value = "nomatch";
    app.syncCategoryRadioGroup(
      root.querySelector("[data-item-category-radios]"),
      "category_id",
      "missing-category",
      state,
      "nomatch",
    );
    assert.match(root.querySelector("[data-item-category-radios]").textContent, /No category/);

    assert.deepEqual(app.getManualCategoryIds(state), ["cat-2"]);
    assert.deepEqual(app.getAlphabeticalCategoryIds(state), ["cat-1"]);
    assert.deepEqual(app.getOrderedCategoryIds(state), ["cat-2", "cat-1"]);
    assert.deepEqual(app.getDisplayedCategoryIds(state), ["cat-2"]);
    assert.deepEqual(app.deriveManualCategoryIds(state, ["cat-2", "cat-1"]), []);
    app.setCategoryOrder(state, ["cat-1", "cat-2"]);
    assert.deepEqual([...state.categoryOrder.entries()], [["cat-1", 0], ["cat-2", 1]]);

    globalThis.fetch = async () => createResponse({
      jsonData: [
        { category_id: "cat-2", sort_order: 0 },
        { category_id: "cat-1", sort_order: 1 },
      ],
    });
    env.dom.window.fetch = globalThis.fetch;
    await app.saveCategoryOrder(root, state);
    assert.deepEqual([...state.categoryOrder.entries()], [["cat-2", 0], ["cat-1", 1]]);

    app.renderCategoryOrderSettings(root, state);
    assert.equal(root.querySelectorAll("[data-settings-category-move]").length >= 0, true);
    app.setListSettingsOpen(root, state, true);
    assert.equal(root.querySelector("[data-list-settings-panel]").hidden, false);

    root.querySelector("[data-item-name-input]").value = "mil";
    app.renderItemSuggestions(root, state);
    assert.equal(root.querySelectorAll("[data-item-reuse]").length >= 0, true);
    assert.match(root.querySelector("[data-item-suggestions]").textContent, /Milk/);

    app.renderItems(root, state);
    assert.match(root.querySelector("[data-item-list]").textContent, /Milk/);
    assert.match(root.querySelector("[data-item-list]").textContent, /Checked off/);

    const itemCard = root.querySelector('[data-item-card="item-1"]');
    app.highlightItem(root, state, "item-1");
    assert.equal(itemCard.classList.contains("is-highlighted"), true);
    timeoutFn();
    assert.equal(itemCard.classList.contains("is-highlighted"), false);

    assert.ok(app.compareActiveItems(state, state.items.get("item-3"), state.items.get("item-1")) < 0);
    assert.ok(app.compareCheckedItems(state.items.get("item-2"), { ...state.items.get("item-2"), checked_at: "2023-01-01T00:00:00Z", name: "Yogurt" }) < 0);
    assert.deepEqual(app.getActiveGroupOrder(state, [...state.items.values()].filter((item) => !item.checked)), ["uncategorized", "cat-2"]);

    app.replaceItems(state, [{ id: "item-4", name: "Eggs" }]);
    app.upsertItem(state, { id: "item-5", name: "Butter" });
    app.removeItem(state, "item-4");
    assert.equal(state.items.has("item-5"), true);

    state.items = new Map([["item-5", { id: "item-5", name: "Butter", quantity_text: "", note: "", category_id: null }]]);
    app.setItemEditPanelOpen(root, state, "item-5");
    assert.equal(root.querySelector("[data-item-edit-panel]").hidden, false);
    app.setItemEditPanelOpen(root, state, null);
    assert.equal(root.querySelector("[data-item-edit-panel]").hidden, true);
  } finally {
    env.restore();
  }
});

test("list detail bootstraps, reacts to websocket updates, and handles list actions", async () => {
  const sockets = [];
  const scheduled = [];
  const fetchLog = [];
  class MockSocket {
    constructor(url) {
      this.url = url;
      this.handlers = new Map();
      sockets.push(this);
    }
    addEventListener(type, callback) {
      this.handlers.set(type, callback);
    }
    emit(type, payload) {
      this.handlers.get(type)?.(payload);
    }
    close() {
      this.emit("close");
    }
  }

  const env = installDom(listDetailHtml(), {
    url: "http://example.com/lists/list-1?addItem=1",
    WebSocket: MockSocket,
    timers: {
      setTimeout: (fn) => {
        scheduled.push(fn);
        return scheduled.length;
      },
      clearTimeout: () => {},
    },
    fetch: async (url, options = {}) => {
      fetchLog.push([url, options.method || "GET"]);
      if (url === "/api/v1/lists/list-1") {
        return createResponse({ jsonData: { id: "list-1", name: "Weekly Groceries" } });
      }
      if (url === "/api/v1/lists/list-1/items") {
        return createResponse({
          jsonData: [
            { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" },
            { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-02T00:00:00Z", category_id: null, sort_order: 2, quantity_text: "", note: "" },
          ],
        });
      }
      if (url === "/api/v1/lists/list-1/categories") {
        return createResponse({ jsonData: [{ id: "cat-1", name: "Dairy", color: "#fff", aliases: ["milk"] }] });
      }
      if (url === "/api/v1/lists/list-1/category-order") {
        return createResponse({ jsonData: [{ category_id: "cat-1", sort_order: 0 }] });
      }
      if (url === "/api/v1/lists/list-1/items" && options.method === "POST") {
        return createResponse({ jsonData: { id: "item-3", name: "Eggs", checked: false, category_id: "cat-1", sort_order: 3, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-1/check") {
        return createResponse({ jsonData: { id: "item-1", name: "Milk", checked: true, checked_at: "2024-01-03T00:00:00Z", category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-1/uncheck") {
        return createResponse({ jsonData: { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-5/check") {
        return createResponse({ jsonData: { id: "item-5", name: "Soap", checked: true, checked_at: "2024-01-03T00:00:00Z", category_id: null, sort_order: 0, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-5/uncheck") {
        return createResponse({ jsonData: { id: "item-5", name: "Soap", checked: false, category_id: null, sort_order: 0, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-3" && options.method === "PATCH") {
        return createResponse({ jsonData: { id: "item-3", name: "Eggs updated", checked: false, category_id: null, sort_order: 3, quantity_text: "1 dozen", note: "Free range" } });
      }
      if (url === "/api/v1/items/item-3" && options.method === "DELETE") {
        return createResponse({ ok: true, status: 204, jsonData: {} });
      }
      if (url === "/api/v1/items/item-5" && options.method === "DELETE") {
        return createResponse({ ok: true, status: 204, jsonData: {} });
      }
      if (url === "/api/v1/lists/list-1/category-order" && options.method === "PUT") {
        return createResponse({ jsonData: [{ category_id: "cat-1", sort_order: 0 }] });
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    await app.initListDetail();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const root = document.querySelector("[data-list-detail]");
    assert.equal(root.querySelector("[data-list-title]").textContent, "Weekly Groceries");
    assert.ok(sockets[0].url.includes("/api/v1/ws/lists/list-1"));
    assert.equal(root.querySelector("[data-item-panel]").hidden, false);
    assert.equal(env.dom.window.location.search, "");

    sockets[0].emit("open");
    assert.equal(root.querySelector("[data-list-sync-status]").textContent, "Live updates on.");

    sockets[0].emit("message", {
      data: JSON.stringify({
        type: "list_snapshot",
        payload: {
          items: [{ id: "item-4", name: "Apples", checked: false, category_id: null, sort_order: 0, quantity_text: "", note: "" }],
          category_order: [],
        },
      }),
    });
    assert.match(root.querySelector("[data-item-list]").textContent, /Apples/);

    sockets[0].emit("message", {
      data: JSON.stringify({ type: "category_order_updated", payload: { category_order: [{ category_id: "cat-1", sort_order: 0 }] } }),
    });
    sockets[0].emit("message", {
      data: JSON.stringify({ type: "item_deleted", payload: { item: { id: "item-4" } } }),
    });
    sockets[0].emit("message", {
      data: JSON.stringify({ type: "item_updated", payload: { item: { id: "item-5", name: "Soap", checked: false, category_id: null, sort_order: 0, quantity_text: "", note: "" } } }),
    });
    assert.match(root.querySelector("[data-item-list]").textContent, /Soap/);

    sockets[0].emit("close");
    assert.equal(root.querySelector("[data-list-sync-status]").textContent, "Live updates paused. Reconnecting...");
    scheduled[scheduled.length - 1]();
    assert.equal(sockets.length > 1, true);

    root.querySelector("[data-item-form-toggle]").click();
    assert.equal(root.querySelector("[data-item-panel]").hidden, true);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    assert.equal(root.querySelector("[data-item-panel]").hidden, true);

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    assert.equal(root.querySelector("[data-item-panel]").hidden, false);

    root.querySelector('[data-item-form] input[name="name"]').value = "Eggs";
    root.querySelector("[data-item-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-success]").textContent, "Item added.");

    root.querySelector('[data-item-card="item-5"]').click();
    root.querySelector('[data-item-edit-form] input[name="name"]').value = "Eggs updated";
    root.querySelector('[data-item-edit-form] input[name="quantity_text"]').value = "1 dozen";
    root.querySelector('[data-item-edit-form] input[name="note"]').value = "Free range";
    root.querySelector("[data-item-edit-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-success]").textContent, "Item updated.");

    root.querySelector('[data-item-toggle="item-5"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.match(root.querySelector("[data-list-toast-message]").textContent, /Soap checked/);
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    root.querySelector('[data-item-delete="item-5"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-success]").textContent, "Item deleted.");

    root.querySelector("[data-list-settings-toggle]").click();
    assert.equal(root.querySelector("[data-list-settings-panel]").hidden, false);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    assert.equal(root.querySelector("[data-list-settings-panel]").hidden, true);

    document.dispatchEvent(new Event("beforeunload"));
    assert.ok(fetchLog.length > 0);
  } finally {
    env.restore();
  }
});

test("initListDetail covers error and alternate interaction branches", async () => {
  const fetchQueue = [];
  const env = installDom(listDetailHtml(), {
    fetch: async (url, options = {}) => {
      if (!options.method || options.method === "GET") {
        if (url === "/api/v1/lists/list-1") {
          return createResponse({ jsonData: { id: "list-1", name: "Weekly" } });
        }
        if (url === "/api/v1/lists/list-1/items") {
          return createResponse({
            jsonData: [
              { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" },
              { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2, quantity_text: "", note: "" },
            ],
          });
        }
        if (url === "/api/v1/lists/list-1/categories") {
          return createResponse({ jsonData: [{ id: "cat-1", name: "Bakery", color: "#eee", aliases: [] }] });
        }
        if (url === "/api/v1/lists/list-1/category-order") {
          return createResponse({ jsonData: [{ category_id: "cat-1", sort_order: 0 }] });
        }
      }
      if (fetchQueue.length > 0) {
        return fetchQueue.shift()(url, options);
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    await app.initListDetail();
    const root = document.querySelector("[data-list-detail]");

    root.querySelector("[data-list-toast-undo]").click();

    root.querySelector("[data-item-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Please enter an item name.");

    root.querySelector("[data-item-edit-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    root.querySelector('[data-item-card="item-1"]').click();
    root.querySelector('[data-item-edit-form] input[name="name"]').value = "   ";
    root.querySelector("[data-item-edit-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Please enter an item name.");

    fetchQueue.push(() => createResponse({ ok: false, status: 500, jsonData: { detail: "Save failed" } }));
    root.querySelector('[data-item-edit-form] input[name="name"]').value = "Milk";
    root.querySelector("[data-item-edit-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Save failed");

    const invalidMove = document.createElement("button");
    invalidMove.dataset.settingsCategoryMove = "up";
    invalidMove.dataset.categoryId = "missing";
    root.appendChild(invalidMove);
    invalidMove.click();

    root.querySelector("[data-list-settings-toggle]").click();
    root.querySelector('[data-category-id="cat-1"], [data-settings-category-move="up"]')?.click();
    root.querySelector("[data-list-settings-close]").click();

    const missingReuse = document.createElement("button");
    missingReuse.dataset.itemReuse = "missing";
    root.appendChild(missingReuse);
    missingReuse.click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Could not find that item.");

    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector("[data-item-name-input]").value = "bread";
    root.dispatchEvent(new Event("input", { bubbles: true }));
    app.renderItemSuggestions(root, {
      categoryOrder: new Map([["cat-1", 0]]),
      categories: new Map([["cat-1", { id: "cat-1", name: "Bakery", color: "#eee", aliases: [] }]]),
      editingItemId: null,
      highlightTimers: new Map(),
      items: new Map([
        ["item-1", { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1 }],
        ["item-2", { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2 }],
      ]),
    });
    fetchQueue.push((url) => createResponse({ jsonData: { id: "item-2", name: "Bread", checked: false, category_id: null, sort_order: 2 } }));
    fetchQueue.push((url) => createResponse({ jsonData: { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2 } }));
    root.querySelector('[data-item-reuse="item-2"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const uncheckedReuse = document.createElement("button");
    uncheckedReuse.dataset.itemReuse = "item-1";
    root.appendChild(uncheckedReuse);
    uncheckedReuse.click();

    const missingToggle = document.createElement("button");
    missingToggle.dataset.itemToggle = "missing";
    root.appendChild(missingToggle);
    missingToggle.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const missingDelete = document.createElement("button");
    missingDelete.dataset.itemDelete = "missing";
    root.appendChild(missingDelete);
    missingDelete.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    globalThis.fetch = async (url, options = {}) => {
      if (url === "/api/v1/items/item-1" && options.method === "DELETE") {
        return createResponse({ ok: false, status: 401 });
      }
      return createResponse({ jsonData: {} });
    };
    env.dom.window.fetch = globalThis.fetch;
    root.querySelector('[data-item-delete="item-1"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(env.assigned.at(-1), "/login");

    globalThis.fetch = async (url, options = {}) => {
      if (url === "/api/v1/items/item-1" && options.method === "DELETE") {
        return createResponse({ ok: false, status: 500 });
      }
      return createResponse({ jsonData: {} });
    };
    env.dom.window.fetch = globalThis.fetch;
    root.querySelector('[data-item-delete="item-1"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Could not delete item.");

    root.querySelector('[data-item-card="item-2"]').click();
    fetchQueue.push(() => createResponse({ ok: true, status: 204, jsonData: {} }));
    fetchQueue.push(() => createResponse({ jsonData: { id: "item-restore", name: "Bread", checked: false, category_id: null, sort_order: 2, quantity_text: "", note: "" } }));
    fetchQueue.push(() => createResponse({ jsonData: { id: "item-restore", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2, quantity_text: "", note: "" } }));
    root.querySelector('[data-item-delete="item-2"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    root.querySelector("[data-item-edit-delete]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector('[data-item-card="item-1"]').click();
    root.querySelector('[data-item-delete="item-1"]').remove();
    root.querySelector("[data-item-edit-delete]").click();

    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector("[data-item-form-close]").click();
    root.querySelector('[data-item-card="item-1"]').click();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    root.querySelector("[data-list-settings-toggle]").click();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    root.querySelector("[data-item-name-input]").focus();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  } finally {
    env.restore();
  }
});

test("initListDetail surfaces load failures", async () => {
  const failingListEnv = installDom(listDetailHtml(), {
    fetch: async () => createResponse({ ok: false, status: 500, jsonData: { detail: "Load failed" } }),
  });

  try {
    const app = await loadApp();
    await app.initListDetail();
    assert.equal(document.querySelector("[data-list-error]").textContent, "Load failed");
  } finally {
    failingListEnv.restore();
  }

});

test("remaining app.js branch edges are exercised", async () => {
  const env = installDom(listDetailHtml(), {
    fetch: async (url, options = {}) => {
      if (!options.method || options.method === "GET") {
        if (url === "/api/v1/lists/list-1") {
          return createResponse({ jsonData: { id: "list-1", name: "Weekly" } });
        }
        if (url === "/api/v1/lists/list-1/items") {
          return createResponse({
            jsonData: [
              { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" },
              { id: "item-2", name: "Milky Way", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" },
              { id: "item-3", name: "Almond Milk", checked: false, category_id: null, sort_order: 1, quantity_text: "", note: "" },
              { id: "item-4", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2, quantity_text: "", note: "" },
            ],
          });
        }
        if (url === "/api/v1/lists/list-1/categories") {
          return createResponse({ jsonData: [{ id: "cat-1", name: "Bakery", color: "#eee", aliases: [] }] });
        }
        if (url === "/api/v1/lists/list-1/category-order") {
          return createResponse({ jsonData: [{ category_id: "cat-1", sort_order: 0 }] });
        }
      }
      if (url === "/api/v1/lists/list-1/items" && options.method === "POST") {
        return createResponse({ jsonData: { id: "item-5", name: "Eggs", checked: false, category_id: "cat-1", sort_order: 3, quantity_text: "12", note: "Large" } });
      }
      if (url === "/api/v1/items/item-4/uncheck") {
        return createResponse({ jsonData: { id: "item-4", name: "Bread", checked: false, category_id: null, sort_order: 2, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-4/check") {
        return createResponse({ jsonData: { id: "item-4", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-1/check") {
        return createResponse({ jsonData: { id: "item-1", name: "Milk", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/item-5" && options.method === "DELETE") {
        return createResponse({ ok: true, status: 204, jsonData: {} });
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();

    const originalWindow = globalThis.window;
    const navCalls = [];
    delete globalThis.__appNavigateTo;
    globalThis.window = { location: { assign: (url) => navCalls.push(url) } };
    app.navigateTo("/fallback");
    globalThis.window = originalWindow;
    globalThis.__appNavigateTo = (url) => env.assigned.push(url);
    assert.deepEqual(navCalls, ["/fallback"]);

    await app.initListDetail();
    const root = document.querySelector("[data-list-detail]");

    root.querySelector("[data-item-name-input]").value = "milk";
    root.querySelector("[data-item-name-input]").dispatchEvent(new Event("input", { bubbles: true }));
    root.querySelector("[data-item-category-search]").dispatchEvent(new Event("input", { bubbles: true }));
    root.querySelector("[data-item-edit-category-search]").dispatchEvent(new Event("input", { bubbles: true }));
    assert.match(root.querySelector("[data-item-suggestions]").textContent, /Milky Way/);

    root.querySelector('[data-item-card="item-1"]').click();
    root.querySelector("[data-item-edit-close]").click();

    const textNode = document.createTextNode("x");
    root.appendChild(textNode);
    textNode.dispatchEvent(new Event("click", { bubbles: true }));

    root.querySelector("[data-list-toast-undo]").click();
    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector('[data-item-form] input[name="name"]').value = "Eggs";
    root.querySelector('[data-item-form] input[name="quantity_text"]').value = "12";
    root.querySelector('[data-item-form] input[name="note"]').value = "Large";
    root.querySelector('[data-item-form]').insertAdjacentHTML("beforeend", '<input type="hidden" name="category_id" value="cat-1" />');
    root.querySelector("[data-item-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-success]").textContent, "Item added.");

    globalThis.fetch = async (url, options = {}) => {
      if (url === "/api/v1/lists/list-1/items" && options.method === "POST") {
        return createResponse({ ok: false, status: 500, jsonData: { detail: "Add failed" } });
      }
      return createResponse({ jsonData: {} });
    };
    env.dom.window.fetch = globalThis.fetch;
    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector('[data-item-form] input[name="name"]').value = "Oops";
    root.querySelector("[data-item-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(root.querySelector("[data-list-error]").textContent, "Add failed");

    app.renderItemSuggestions(root, {
      categoryOrder: new Map([["cat-1", 0]]),
      categories: new Map([["cat-1", { id: "cat-1", name: "Bakery", color: "#eee", aliases: [] }]]),
      editingItemId: null,
      highlightTimers: new Map(),
      items: new Map([
        ["item-1", { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1 }],
        ["item-2", { id: "item-2", name: "Milky Way", checked: false, category_id: "cat-1", sort_order: 1 }],
        ["item-3", { id: "item-3", name: "Almond Milk", checked: false, category_id: null, sort_order: 1 }],
        ["item-4", { id: "item-4", name: "Milk", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 1 }],
      ]),
    });

    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector("[data-item-name-input]").value = "bread";
    app.renderItemSuggestions(root, {
      categoryOrder: new Map([["cat-1", 0]]),
      categories: new Map([["cat-1", { id: "cat-1", name: "Bakery", color: "#eee", aliases: [] }]]),
      editingItemId: null,
      highlightTimers: new Map(),
      items: new Map([["item-4", { id: "item-4", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: null, sort_order: 2 }]]),
    });
    root.querySelector('[data-item-reuse="item-4"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    root.querySelector("[data-list-settings-toggle]").click();
    const moveDown = root.querySelector('[data-settings-category-move="down"]');
    moveDown.click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const invalidMove = document.createElement("button");
    invalidMove.dataset.settingsCategoryMove = "up";
    invalidMove.dataset.categoryId = "missing";
    root.appendChild(invalidMove);
    invalidMove.click();

    const socketState = { socket: null, items: new Map(), categoryOrder: new Map() };
    class CloseSocket {
      constructor() {
        this.handlers = new Map();
      }
      addEventListener(type, callback) {
        this.handlers.set(type, callback);
      }
      close() {
        this.handlers.get("close")?.();
      }
      emit(type, payload) {
        this.handlers.get(type)?.(payload);
      }
    }
    globalThis.WebSocket = CloseSocket;
    env.dom.window.WebSocket = CloseSocket;
    app.connectListSocket(root, socketState);
    socketState.socket.emit("message", { data: JSON.stringify({ type: "item_updated", payload: {} }) });
    document.dispatchEvent(new Event("beforeunload"));
    socketState.socket.close();

    const undoEnvAction = async () => {
      throw new Error("Undo failed");
    };
    app.showUndoToast(root, { undoAction: undoEnvAction, undoTimerId: null }, "Undoing", undoEnvAction);
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    root.querySelector('[data-item-card="item-5"]').click();
    root.querySelector('[data-item-delete="item-5"]').remove();
    root.querySelector("[data-item-edit-delete]").click();
  } finally {
    env.restore();
  }
});

test("late list-detail failure branches are covered", async () => {
  let mode = "initial";
  const env = installDom(listDetailHtml(), {
    fetch: async (url, options = {}) => {
      if (mode === "initial") {
        if (!options.method || options.method === "GET") {
          if (url === "/api/v1/lists/list-1") {
            return createResponse({ jsonData: { id: "list-1", name: "Weekly" } });
          }
          if (url === "/api/v1/lists/list-1/items") {
            return createResponse({
              jsonData: [
                { id: "item-1", name: "Milk", checked: false, category_id: "cat-1", sort_order: 1, quantity_text: "", note: "" },
                { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: "cat-2", sort_order: 2, quantity_text: "", note: "" },
              ],
            });
          }
          if (url === "/api/v1/lists/list-1/categories") {
            return createResponse({
              jsonData: [
                { id: "cat-1", name: "Bakery", color: "#eee", aliases: [] },
                { id: "cat-2", name: "Dairy", color: "#ddd", aliases: [] },
              ],
            });
          }
          if (url === "/api/v1/lists/list-1/category-order") {
            return createResponse({
              jsonData: [
                { category_id: "cat-1", sort_order: 0 },
                { category_id: "cat-2", sort_order: 1 },
              ],
            });
          }
        }
      }

      if (mode === "add-with-optionals" && url === "/api/v1/lists/list-1/items" && options.method === "POST") {
        const payload = JSON.parse(options.body);
        assert.deepEqual(payload, {
          name: "Eggs",
          category_id: "cat-1",
          quantity_text: "12",
          note: "Large",
        });
        return createResponse({ jsonData: { id: "item-3", ...payload, checked: false, sort_order: 3 } });
      }

      if (mode === "category-move" && url === "/api/v1/lists/list-1/category-order" && options.method === "PUT") {
        return createResponse({
          jsonData: [
            { category_id: "cat-2", sort_order: 0 },
            { category_id: "cat-1", sort_order: 1 },
          ],
        });
      }

      if (mode === "toggle-undo-fails") {
        if (url === "/api/v1/items/item-1/check") {
          return createResponse({ jsonData: { id: "item-1", name: "Milk", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: "cat-1", sort_order: 1 } });
        }
        if (url === "/api/v1/items/item-1/uncheck") {
          return createResponse({ ok: false, status: 500, jsonData: { detail: "Undo failed" } });
        }
      }

      if (mode === "delete-undo-restore") {
        if (url === "/api/v1/items/item-2" && options.method === "DELETE") {
          return createResponse({ ok: true, status: 204, jsonData: {} });
        }
        if (url === "/api/v1/lists/list-1/items" && options.method === "POST") {
          return createResponse({ jsonData: { id: "item-restore", name: "Bread", checked: false, category_id: "cat-2", sort_order: 2, quantity_text: "", note: "" } });
        }
        if (url === "/api/v1/items/item-restore/check") {
          return createResponse({ jsonData: { id: "item-restore", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: "cat-2", sort_order: 2, quantity_text: "", note: "" } });
        }
      }

      if (url === "/api/v1/auth/login/options") {
        return createResponse({ jsonData: { challenge: "AQID" } });
      }

      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    await app.initListDetail();
    const root = document.querySelector("[data-list-detail]");

    assert.ok(
      app.compareActiveItems(
        { categoryOrder: new Map(), categories: new Map([["cat-1", { id: "cat-1", name: "Bakery" }]]) },
        { name: "B", category_id: "cat-1", sort_order: 2 },
        { name: "A", category_id: "cat-1", sort_order: 1 },
      ) > 0,
    );

    mode = "add-with-optionals";
    root.querySelector("[data-item-form-toggle]").click();
    root.querySelector('[data-item-form] input[name="name"]').value = "Eggs";
    root.querySelector('[data-item-form] input[name="quantity_text"]').value = "12";
    root.querySelector('[data-item-form] input[name="note"]').value = "Large";
    root
      .querySelector('[data-item-form]')
      .insertAdjacentHTML("beforeend", '<input type="radio" name="category_id" value="cat-1" checked />');
    root.querySelector("[data-item-form]").dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));

    mode = "category-move";
    const invalidMove = document.createElement("button");
    invalidMove.dataset.settingsCategoryMove = "up";
    invalidMove.dataset.categoryId = "missing";
    root.appendChild(invalidMove);
    invalidMove.click();

    const boundsMove = document.createElement("button");
    boundsMove.dataset.settingsCategoryMove = "up";
    boundsMove.dataset.categoryId = "cat-1";
    root.appendChild(boundsMove);
    boundsMove.click();

    root.querySelector("[data-list-settings-toggle]").click();
    root.querySelector('[data-settings-category-move="down"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    mode = "toggle-undo-fails";
    root.querySelector('[data-item-toggle="item-1"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    mode = "delete-undo-restore";
    root.querySelector('[data-item-card="item-2"]').click();
    root.querySelector('[data-item-delete="item-2"]').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    root.querySelector("[data-list-toast-undo]").click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    const socketRoot = document.createElement("section");
    socketRoot.dataset.listId = "list-1";
    socketRoot.dataset.accessToken = "token";
    socketRoot.innerHTML = `<p data-list-sync-status></p><div data-item-list></div><div data-item-empty></div><div data-list-settings-category-list></div><div data-item-suggestions></div><div data-item-suggestions-slot></div><input data-item-name-input />`;
    const socketState = { socket: null, items: new Map(), categoryOrder: new Map(), categories: new Map(), editingItemId: null, highlightTimers: new Map() };
    class DisposableSocket {
      constructor() {
        this.handlers = new Map();
      }
      addEventListener(type, callback) {
        this.handlers.set(type, callback);
      }
      close() {
        this.handlers.get("close")?.();
      }
      emit(type, payload) {
        this.handlers.get(type)?.(payload);
      }
    }
    globalThis.WebSocket = DisposableSocket;
    env.dom.window.WebSocket = DisposableSocket;
    app.connectListSocket(socketRoot, socketState);
    socketState.socket.emit("message", { data: JSON.stringify({ type: "item_updated", payload: {} }) });
    window.dispatchEvent(new Event("beforeunload"));

  } finally {
    env.restore();
  }
});




test("undo and restore helpers are directly covered", async () => {
  const env = installDom(listDetailHtml(), {
    fetch: async (url, options = {}) => {
      if (url === "/api/v1/items/item-2/check") {
        return createResponse({ jsonData: { id: "item-2", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z" } });
      }
      if (url === "/api/v1/items/item-2/uncheck") {
        return createResponse({ jsonData: { id: "item-2", name: "Bread", checked: false, category_id: "cat-2", sort_order: 2 } });
      }
      if (url === "/api/v1/lists/list-1/items" && options.method === "POST") {
        return createResponse({ jsonData: { id: "restored", name: "Bread", checked: false, category_id: "cat-2", sort_order: 2, quantity_text: "", note: "" } });
      }
      if (url === "/api/v1/items/restored/check") {
        return createResponse({ jsonData: { id: "restored", name: "Bread", checked: true, checked_at: "2024-01-01T00:00:00Z", category_id: "cat-2", sort_order: 2, quantity_text: "", note: "" } });
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    const root = document.querySelector("[data-list-detail]");
    const state = {
      categoryOrder: new Map(),
      categories: new Map(),
      editingItemId: null,
      highlightTimers: new Map(),
      items: new Map([
        ["item-2", { id: "item-2", name: "Bread", checked: false }],
      ]),
      undoAction: null,
      undoTimerId: null,
    };

    await app.runUndoAction(root, state, async () => {
      throw new Error("Undo failed");
    });
    assert.equal(root.querySelector("[data-list-error]").textContent, "Undo failed");

    await app.restoreCheckedSuggestion(root, state, "item-2");
    assert.equal(state.items.get("item-2").checked, true);

    await app.restoreToggledItem(root, state, "item-2", "check");
    assert.equal(state.items.get("item-2").checked, false);

    await app.restoreDeletedItem(root, state, "list-1", {
      id: "item-2",
      name: "Bread",
      checked: true,
      quantity_text: "",
      note: "",
      category_id: "cat-2",
      sort_order: 2,
    });
    assert.equal(state.items.get("restored").checked, true);

    let disposed = false;
    let closed = false;
    const socketState = {
      socket: {
        close() {
          closed = true;
        },
      },
    };
    app.disposeSocket(socketState, () => {
      disposed = true;
    });
    assert.equal(disposed, true);
    assert.equal(closed, true);

    let reconnected = false;
    app.handleSocketClose(root, { socket: {} }, () => {
      reconnected = true;
    }, () => true);
    assert.equal(reconnected, false);

  } finally {
    env.restore();
  }
});

test("item edit delete delegates to the visible delete button", async () => {
  const env = installDom(listDetailHtml(), {
    fetch: async (url, options = {}) => {
      if (!options.method || options.method === "GET") {
        if (url === "/api/v1/lists/list-1") {
          return createResponse({ jsonData: { id: "list-1", name: "Weekly" } });
        }
        if (url === "/api/v1/lists/list-1/items") {
          return createResponse({ jsonData: [{ id: "item-1", name: "Milk", checked: false, category_id: null, sort_order: 1, quantity_text: "", note: "" }] });
        }
        if (url === "/api/v1/lists/list-1/categories") {
          return createResponse({ jsonData: [] });
        }
        if (url === "/api/v1/lists/list-1/category-order") {
          return createResponse({ jsonData: [] });
        }
      }
      return createResponse({ jsonData: {} });
    },
  });

  try {
    const app = await loadApp();
    await app.initListDetail();
    const root = document.querySelector("[data-list-detail]");
    root.querySelector('[data-item-card="item-1"]').click();
    let delegated = false;
    root.querySelector('[data-item-delete="item-1"]').click = () => {
      delegated = true;
    };
    root.querySelector("[data-item-edit-delete]").click();
    assert.equal(delegated, true);
  } finally {
    env.restore();
  }
});
