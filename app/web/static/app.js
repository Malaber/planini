const LANGUAGE_COOKIE_NAME = "planini_locale";
const OFFLINE_LIST_STORAGE_PREFIX = "planini:list-offline:";
const OFFLINE_ITEM_ID_PREFIX = "local-item-";
const OFFLINE_MUTATION_ID_PREFIX = "local-mutation-";
const ITEM_HIDE_DURATION_MS = 4 * 60 * 60 * 1000;
const ITEM_SWIPE_TRIGGER_PX = 72;
const ITEM_SWIPE_LIMIT_PX = 132;
const UNDO_ACTION_DURATION_MS = 10000;
const MOVED_ITEM_NOTICE_FADE_MS = 260;
const SUPPORTED_LANGUAGE_OPTIONS = [
  { value: "", label: "Browser default" },
  { value: "en", label: "English" },
  { value: "de", label: "Deutsch" },
];
const CATEGORY_SWATCH_FALLBACK_COLOR = "#d9c5b3";
const CHECKED_CATEGORY_SWATCH_COLOR = "#b59676";
const ITEM_EDIT_LIVE_SAVE_DELAY_MS = 900;
const ITEM_EDIT_HISTORY_LIMIT = 5;

function isItemHidden(item, nowMs = Date.now()) {
  const hiddenUntilMs = Date.parse(item.hidden_until || "");
  return Number.isFinite(hiddenUntilMs) && hiddenUntilMs > nowMs;
}

function formatHiddenUntilLabel(item, nowMs = Date.now()) {
  const hiddenUntilMs = Date.parse(item.hidden_until || "");
  if (!Number.isFinite(hiddenUntilMs) || hiddenUntilMs <= nowMs) {
    return "";
  }

  const remainingMinutes = Math.ceil((hiddenUntilMs - nowMs) / 60000);
  if (remainingMinutes >= 60) {
    return `${Math.ceil(remainingMinutes / 60)}h`;
  }
  return `${remainingMinutes}m`;
}

function base64UrlToBytes(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const decoded = atob(padded);
  return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
}

function bytesToBase64Url(value) {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function normalizeLanguagePreference(value) {
  return SUPPORTED_LANGUAGE_OPTIONS.some((option) => option.value === value) ? value : "";
}

function getBrowserLanguage() {
  if (typeof navigator === "undefined") {
    return "en";
  }

  if (Array.isArray(navigator.languages) && navigator.languages.length > 0) {
    return navigator.languages[0];
  }

  return navigator.language || "en";
}

function getStoredLanguagePreference() {
  if (typeof document === "undefined") {
    return "";
  }

  const cookie = document.cookie
    .split(";")
    .map((entry) => entry.trim())
    .find((entry) => entry.startsWith(`${LANGUAGE_COOKIE_NAME}=`));
  if (!cookie) {
    return "";
  }

  return normalizeLanguagePreference(decodeURIComponent(cookie.split("=").slice(1).join("=")));
}

function storeLanguagePreference(value) {
  const normalized = normalizeLanguagePreference(value);
  if (typeof document === "undefined") {
    return normalized;
  }

  if (normalized) {
    document.cookie = `${LANGUAGE_COOKIE_NAME}=${encodeURIComponent(normalized)}; path=/; max-age=31536000; SameSite=Lax`;
  } else {
    document.cookie = `${LANGUAGE_COOKIE_NAME}=; path=/; max-age=0; SameSite=Lax`;
  }

  return normalized;
}

function getPreferredLocale() {
  return getStoredLanguagePreference() || getCurrentLocale();
}

function applyLanguagePreference(value = getStoredLanguagePreference()) {
  const normalized = normalizeLanguagePreference(value);
  if (typeof document !== "undefined") {
    document.documentElement.lang = normalized || getCurrentLocale();
  }
  return normalized;
}

function languagePreferenceLabel(value) {
  const normalized = normalizeLanguagePreference(value);
  const option = SUPPORTED_LANGUAGE_OPTIONS.find((entry) => entry.value === normalized);
  if (!option || !normalized) {
    return translate(
      "settings.language_browser_default_with_locale",
      { locale: getCurrentLocale() },
      "Browser default ({locale})"
    );
  }
  return option.label;
}

function syncLanguageSettings(root) {
  const preference = applyLanguagePreference();
  const select = root.querySelector("[data-language-settings-select]");
  const summary = root.querySelector("[data-language-settings-summary]");

  if (select instanceof HTMLSelectElement) {
    select.value = preference;
  }

  if (summary instanceof HTMLElement) {
    summary.textContent = languagePreferenceLabel(preference);
  }
}

function setLanguageSettingsOpen(root, isOpen) {
  const overlay = root.querySelector("[data-language-settings-overlay]");
  const panel = root.querySelector("[data-language-settings-panel]");
  if (!(overlay instanceof HTMLElement) || !(panel instanceof HTMLElement)) {
    return;
  }

  overlay.hidden = !isOpen;
  panel.hidden = !isOpen;
  if (isOpen) {
    syncLanguageSettings(root);
    root.querySelector("[data-language-settings-select]")?.focus();
  }
}

function publicKeyFromJSON(publicKey) {
  const parsed = { ...publicKey, challenge: base64UrlToBytes(publicKey.challenge) };

  if (parsed.user?.id) {
    parsed.user = { ...parsed.user, id: base64UrlToBytes(parsed.user.id) };
  }

  if (Array.isArray(parsed.excludeCredentials)) {
    parsed.excludeCredentials = parsed.excludeCredentials.map((credential) => ({
      ...credential,
      id: base64UrlToBytes(credential.id),
    }));
  }

  if (Array.isArray(parsed.allowCredentials)) {
    parsed.allowCredentials = parsed.allowCredentials.map((credential) => ({
      ...credential,
      id: base64UrlToBytes(credential.id),
    }));
  }

  return parsed;
}

function credentialToJSON(value) {
  if (value instanceof ArrayBuffer) {
    return bytesToBase64Url(value);
  }

  if (ArrayBuffer.isView(value)) {
    return bytesToBase64Url(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
  }

  if (Array.isArray(value)) {
    return value.map(credentialToJSON);
  }

  if (value && typeof value.toJSON === "function") {
    return credentialToJSON(value.toJSON());
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, inner]) => [key, credentialToJSON(inner)]));
  }

  return value;
}

function getI18nState() {
  const state = globalThis.__appI18n;
  if (!state || typeof state !== "object") {
    return { locale: "en", catalog: {} };
  }
  if ((!state.catalog || typeof state.catalog !== "object") && typeof state.catalogBase64 === "string") {
    try {
      state.catalog = JSON.parse(atob(state.catalogBase64));
    } catch {
      state.catalog = {};
    }
  }
  return {
    locale: typeof state.locale === "string" ? state.locale : "en",
    catalog: state.catalog && typeof state.catalog === "object" ? state.catalog : {},
  };
}

function getCurrentLocale() {
  return getI18nState().locale || "en";
}

function resolveTranslation(key) {
  return key.split(".").reduce((current, part) => {
    if (!current || typeof current !== "object") {
      return undefined;
    }
    return current[part];
  }, getI18nState().catalog);
}

function interpolateTranslation(template, params = {}) {
  return template.replace(/\{(\w+)\}/g, (_, key) => String(params[key] ?? `{${key}}`));
}

function translate(key, params = {}, fallback = key) {
  const value = resolveTranslation(key);
  if (typeof value !== "string") {
    return interpolateTranslation(fallback, params);
  }
  return interpolateTranslation(value, params);
}

function translatePlural(key, count, params = {}, fallback = {}) {
  const locale = getCurrentLocale();
  const category = new Intl.PluralRules(locale).select(count);
  const entry = resolveTranslation(key);
  if (entry && typeof entry === "object") {
    const template = entry[category] || entry.other;
    if (typeof template === "string") {
      return interpolateTranslation(template, { count, ...params });
    }
  }
  const template = count === 1 ? fallback.one : fallback.other;
  return interpolateTranslation(template || "{count}", { count, ...params });
}

function navigateTo(url) {
  if (typeof globalThis.__appNavigateTo === "function") {
    globalThis.__appNavigateTo(url);
    return;
  }

  window.location.assign(url);
}

async function registerServiceWorker() {
  if (typeof window === "undefined" || typeof navigator === "undefined") {
    return null;
  }

  if (!("serviceWorker" in navigator)) {
    return null;
  }

  if (navigator.webdriver) {
    return null;
  }

  return navigator.serviceWorker.register("/service-worker.js");
}

async function postJson(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (response.status === 401) {
    navigateTo("/login");
    throw new Error(translate("common.errors.unauthorized", {}, "Unauthorized"));
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof data.detail === "string"
      ? data.detail
      : translate("common.errors.passkey_request_failed", {}, "Passkey request failed.");
    throw new Error(message);
  }

  return data;
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (response.status === 401) {
    navigateTo("/login");
    throw new Error(translate("common.errors.unauthorized", {}, "Unauthorized"));
  }
  const data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const message = typeof data.detail === "string"
      ? data.detail
      : translate("common.errors.request_failed", {}, "Request failed.");
    throw new Error(message);
  }

  return data;
}

function setMessage(root, type, message) {
  const errorNode = root.querySelector("[data-auth-error]");
  const successNode = root.querySelector("[data-auth-success]");

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (type === "error") {
    errorNode.hidden = false;
    errorNode.textContent = message;
    return;
  }

  successNode.hidden = false;
  successNode.textContent = message;
}

function toggleButtons(root, disabled) {
  root.querySelectorAll("button").forEach((button) => {
    button.disabled = disabled;
  });
}

function setPasskeyManagementMessage(root, type, message) {
  const errorNode = root.querySelector("[data-passkey-error]");
  const successNode = root.querySelector("[data-passkey-success]");

  if (!errorNode || !successNode) {
    return;
  }

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (!message) {
    return;
  }

  if (type === "error") {
    errorNode.hidden = false;
    errorNode.textContent = message;
    return;
  }

  successNode.hidden = false;
  successNode.textContent = message;
}

function setDashboardMessage(root, type, message) {
  const errorNode = root.querySelector("[data-dashboard-error]");
  const successNode = root.querySelector("[data-dashboard-success]");

  if (!errorNode || !successNode) {
    return;
  }

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (!message) {
    return;
  }

  if (type === "error") {
    errorNode.hidden = false;
    errorNode.textContent = message;
    return;
  }

  successNode.hidden = false;
  successNode.textContent = message;
}

function setInviteMessage(root, type, message) {
  const errorNode = root.querySelector("[data-invite-error]");
  const successNode = root.querySelector("[data-invite-success]");

  if (!errorNode || !successNode) {
    return;
  }

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (!message) {
    return;
  }

  if (type === "error") {
    errorNode.hidden = false;
    errorNode.textContent = message;
    return;
  }

  successNode.hidden = false;
  successNode.textContent = message;
}

function toggleDashboardForms(root, disabled) {
  root
    .querySelectorAll("[data-dashboard] button, [data-dashboard] input, [data-dashboard] select")
    .forEach((node) => {
      const locked = node.getAttribute("data-passkey-locked") === "true";
      node.disabled = disabled || locked;
    });
}

function syncDashboardModalState(root) {
  const overlays = [
    root.querySelector("[data-dashboard-add-overlay]"),
    root.querySelector("[data-dashboard-household-overlay]"),
    root.querySelector("[data-dashboard-list-overlay]"),
  ];
  const hasModalOpen = overlays.some((overlay) => overlay instanceof HTMLElement && !overlay.hidden);
  document.body.classList.toggle("has-list-modal-open", hasModalOpen);
}

function setDashboardPanelOpen(root, panelName, isOpen) {
  const panels = {
    add: {
      overlay: root.querySelector("[data-dashboard-add-overlay]"),
      panel: root.querySelector("[data-dashboard-add-panel]"),
    },
    household: {
      overlay: root.querySelector("[data-dashboard-household-overlay]"),
      panel: root.querySelector("[data-dashboard-household-panel]"),
      focus: root.querySelector("[data-household-name-input]"),
    },
    list: {
      overlay: root.querySelector("[data-dashboard-list-overlay]"),
      panel: root.querySelector("[data-dashboard-list-panel]"),
      focus: root.querySelector("[data-list-name-input]"),
    },
  };
  const toggle = root.querySelector("[data-dashboard-add-toggle]");

  Object.entries(panels).forEach(([name, nodes]) => {
    const shouldOpen = isOpen && name === panelName;
    if (nodes.overlay instanceof HTMLElement) {
      nodes.overlay.hidden = !shouldOpen;
    }
    if (nodes.panel instanceof HTMLElement) {
      nodes.panel.hidden = !shouldOpen;
    }
  });

  if (toggle instanceof HTMLElement) {
    toggle.setAttribute("aria-expanded", String(isOpen));
  }

  syncDashboardModalState(root);

  if (isOpen) {
    const activePanel = panels[panelName];
    if (activePanel?.focus instanceof HTMLElement) {
      window.setTimeout(() => {
        activePanel.focus.focus();
      }, 0);
    }
  }
}

function updateHouseholdOptions(root, households) {
  const select = root.querySelector("[data-household-select]");
  if (!select) {
    return;
  }

  const currentValue = select.value;
  select.innerHTML = "";

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = households.length
    ? translate("dashboard.select_household", {}, "Select a household")
    : translate("dashboard.create_household_first", {}, "Create a household first");
  select.appendChild(placeholder);

  households.forEach((household) => {
    const option = document.createElement("option");
    option.value = household.id;
    option.textContent = household.name;
    select.appendChild(option);
  });

  if (households.some((household) => household.id === currentValue)) {
    select.value = currentValue;
  } else if (households.length === 1) {
    select.value = households[0].id;
  }
}

function updateDashboardListOptions(root, households, listsByHousehold) {
  const group = root.querySelector("[data-dashboard-list-group]");
  const emptyState = root.querySelector("[data-dashboard-list-empty]");
  if (!group || !emptyState) {
    return;
  }

  const listOptions = households.flatMap((household) =>
    (listsByHousehold.get(household.id) || []).map((list) => ({
      householdName: household.name,
      id: list.id,
      name: list.name,
    }))
  );

  group.innerHTML = "";
  emptyState.hidden = listOptions.length > 0;
  if (!emptyState.hidden) {
    group.appendChild(emptyState);
    return;
  }

  listOptions.forEach((list) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "dashboard-add-list-button";
    button.setAttribute("data-dashboard-open-list", list.id);
    button.innerHTML = `
      <strong>${list.name}</strong>
      <small>${list.householdName}</small>
    `;
    group.appendChild(button);
  });
}

function renderHouseholds(root, households, listsByHousehold) {
  const container = root.querySelector("[data-household-list]");
  const emptyState = root.querySelector("[data-dashboard-empty]");
  if (!container || !emptyState) {
    return;
  }

  container.innerHTML = "";
  const hasHouseholds = households.length > 0;
  emptyState.hidden = hasHouseholds;
  emptyState.style.display = hasHouseholds ? "none" : "";

  households.forEach((household) => {
    const lists = listsByHousehold.get(household.id) || [];
    const card = document.createElement("article");
    card.className = "household-card";
    card.innerHTML = `
      <div class="household-card-header">
        <div>
          <h3>${household.name}</h3>
          <p class="household-meta">${translatePlural("dashboard.list_count", lists.length, {}, { one: "{count} list", other: "{count} lists" })}</p>
        </div>
        <button type="button" class="secondary-button" data-create-invite="${household.id}">
          ${translate("dashboard.create_invite_link", {}, "Create invite link")}
        </button>
      </div>
      <div class="household-invite-output" data-invite-output="${household.id}" hidden>
        <p class="dashboard-helper">${translate("dashboard.share_invite_hint", {}, "Share this link within 24 hours:")}</p>
        <div class="household-invite-row">
          <input type="text" readonly data-invite-link-input="${household.id}" />
          <button type="button" class="secondary-button" data-copy-invite="${household.id}">
            ${translate("common.copy", {}, "Copy")}
          </button>
        </div>
      </div>
    `;

    const listGrid = document.createElement("ul");
    listGrid.className = "list-grid";

    if (lists.length === 0) {
      const emptyListState = document.createElement("li");
      emptyListState.innerHTML = `
        <button type="button" class="dashboard-action-card" data-dashboard-add-option="list">
          <strong>${translate("dashboard.add_list", {}, "List")}</strong>
          <small>${translate("dashboard.no_lists_yet", {}, "No lists yet. Add the first list for this household.")}</small>
        </button>
      `;
      listGrid.appendChild(emptyListState);
      card.appendChild(listGrid);
    } else {
      lists.forEach((list) => {
        const openItemCount = Number.isInteger(list.open_item_count) ? list.open_item_count : 0;
        const item = document.createElement("li");
        item.innerHTML = `
          <a href="/lists/${list.id}">
            <strong>${list.name}</strong>
            <small>${translatePlural("dashboard.open_item_count", openItemCount, {}, { one: "{count} open item", other: "{count} open items" })}</small>
          </a>
        `;
        listGrid.appendChild(item);
      });
      card.appendChild(listGrid);
    }

    container.appendChild(card);
  });
}

function formatPasskeyDate(value) {
  if (!value) {
    return translate("settings.never_used", {}, "Never used yet");
  }

  return new Date(value).toLocaleString(getPreferredLocale(), {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function renderPasskeys(root, passkeys) {
  const container = root.querySelector("[data-passkey-list]");
  const emptyState = root.querySelector("[data-passkey-empty]");
  if (!container || !emptyState) {
    return;
  }

  container.innerHTML = "";
  const hasPasskeys = passkeys.length > 0;
  emptyState.hidden = hasPasskeys;
  emptyState.style.display = hasPasskeys ? "none" : "";

  passkeys.forEach((passkey, index) => {
    const row = document.createElement("article");
    row.className = "passkey-row";
    row.innerHTML = `
      <div class="passkey-copy">
        <strong>${passkey.name}</strong>
        <span>${translate("settings.added_on", { date: formatPasskeyDate(passkey.created_at) }, "Added {date}")}</span>
        <span>${translate("settings.last_used", { date: formatPasskeyDate(passkey.last_used_at) }, "Last used {date}")}</span>
      </div>
      <div class="passkey-actions">
        <button
          type="button"
          class="secondary-button"
          data-passkey-rename="${passkey.id}"
          data-passkey-current-name="${passkey.name}"
        >
          ${translate("settings.rename", {}, "Rename")}
        </button>
        <button
          type="button"
          class="danger-button"
          data-passkey-delete="${passkey.id}"
          data-passkey-locked="${passkeys.length <= 1 ? "true" : "false"}"
          ${
            passkeys.length <= 1
              ? `title="${translate("settings.delete_disabled", {}, "Add another passkey before deleting this one.")}" aria-disabled="true"`
              : ""
          }
          ${passkeys.length <= 1 ? "disabled" : ""}
        >
          ${translate("common.delete", {}, "Delete")}
        </button>
      </div>
    `;
    container.appendChild(row);
  });
}

function suggestedPasskeyName(root) {
  return translate(
    "settings.suggested_name",
    { number: root.querySelectorAll(".passkey-row").length + 1 },
    "Passkey {number}"
  );
}

function setPasskeyNameFormState(root, state) {
  const form = root.querySelector("[data-passkey-name-form]");
  const input = root.querySelector("[data-passkey-name-input]");
  const addButton = root.querySelector("[data-passkey-add]");
  const title = root.querySelector("[data-passkey-name-title]");
  const submitButton = root.querySelector("[data-passkey-name-submit]");
  if (
    !(form instanceof HTMLFormElement)
    || !(input instanceof HTMLInputElement)
    || !(title instanceof HTMLElement)
    || !(submitButton instanceof HTMLButtonElement)
  ) {
    return;
  }

  const isOpen = Boolean(state);
  form.hidden = !isOpen;
  if (addButton instanceof HTMLButtonElement) {
    addButton.hidden = isOpen;
  }

  if (!isOpen) {
    form.dataset.mode = "";
    form.dataset.passkeyId = "";
    title.textContent = translate("settings.name_this_passkey", {}, "Name this passkey");
    submitButton.textContent = translate("common.continue", {}, "Continue");
    form.reset();
    return;
  }

  form.dataset.mode = state.mode;
  form.dataset.passkeyId = state.passkeyId || "";
  title.textContent = state.title;
  submitButton.textContent = state.submitLabel;
  input.value = state.name;
  window.setTimeout(() => {
    input.focus();
    input.select();
  }, 0);
}

async function copyText(value) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }

  const helper = document.createElement("textarea");
  helper.value = value;
  helper.setAttribute("readonly", "");
  helper.style.position = "absolute";
  helper.style.left = "-9999px";
  document.body.appendChild(helper);
  helper.select();
  document.execCommand("copy");
  document.body.removeChild(helper);
}

async function loadDashboardData(root) {
  const households = await fetchJson("/api/v1/households");
  const listResponses = await Promise.all(
    households.map(async (household) => ({
      householdId: household.id,
      lists: await fetchJson(`/api/v1/households/${household.id}/lists`),
    }))
  );
  const listsByHousehold = new Map(
    listResponses.map((response) => [response.householdId, response.lists])
  );

  updateHouseholdOptions(root, households);
  updateDashboardListOptions(root, households, listsByHousehold);
  renderHouseholds(root, households, listsByHousehold);
}

async function loadPasskeyManagementData(root) {
  const passkeys = await fetchJson("/api/v1/auth/passkeys");
  renderPasskeys(root, passkeys);
}

function togglePasskeyManagementForms(root, disabled) {
  root
    .querySelectorAll("[data-passkey-management] button, [data-passkey-management] input")
    .forEach((node) => {
      const locked = node.getAttribute("data-passkey-locked") === "true";
      node.disabled = disabled || locked;
    });
}

function syncPasskeyManagementModalState(root) {
  const deleteOverlay = root.querySelector("[data-passkey-delete-overlay]");
  const hasModalOpen = deleteOverlay instanceof HTMLElement && !deleteOverlay.hidden;
  document.body.classList.toggle("has-list-modal-open", hasModalOpen);
}

function setPasskeyDeleteConfirmState(root, state) {
  const overlay = root.querySelector("[data-passkey-delete-overlay]");
  const panel = root.querySelector("[data-passkey-delete-panel]");
  const confirmButton = root.querySelector("[data-passkey-delete-confirm]");
  const copyNode = root.querySelector("[data-passkey-delete-copy]");
  if (
    !(overlay instanceof HTMLElement)
    || !(panel instanceof HTMLElement)
    || !(confirmButton instanceof HTMLButtonElement)
  ) {
    return;
  }

  const isOpen = Boolean(state);
  overlay.hidden = !isOpen;
  panel.hidden = !isOpen;
  const passkeyName = state?.name || translate("settings.delete_target_fallback", {}, "this passkey");
  if (copyNode instanceof HTMLElement) {
    const emphasisNode = document.createElement("strong");
    emphasisNode.textContent = translate("settings.delete_help_emphasis", {}, "another");
    copyNode.replaceChildren(
      document.createTextNode(
        translate(
          "settings.delete_help_prefix",
          { name: passkeyName },
          "To delete {name}, you must authenticate with "
        )
      ),
      emphasisNode,
      document.createTextNode(
        translate(
          "settings.delete_help_suffix",
          {},
          " passkey to confirm you still have a working Passkey after deleting one."
        )
      )
    );
  }
  confirmButton.dataset.passkeyId = state?.passkeyId || "";
  syncPasskeyManagementModalState(root);

  if (isOpen) {
    window.setTimeout(() => {
      confirmButton.focus();
    }, 0);
  }
}

function initPasskeyManagement(root, options = {}) {
  if (!root) {
    return;
  }

  const {
    setMessage = setPasskeyManagementMessage,
    toggleForms = togglePasskeyManagementForms,
    refreshData = () => loadPasskeyManagementData(root),
  } = options;

  const refresh = async () => {
    setMessage(root, "", "");
    await refreshData();
  };

  const passkeyNameForm = root.querySelector("[data-passkey-name-form]");

  root.addEventListener("click", async (event) => {
    const addPasskeyButton = event.target.closest("[data-passkey-add]");
    if (addPasskeyButton) {
      if (!window.PublicKeyCredential || !navigator.credentials) {
        setMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
        return;
      }
      setMessage(root, "", "");
      setPasskeyNameFormState(root, {
        mode: "add",
        passkeyId: "",
        title: translate("settings.name_this_passkey", {}, "Name this passkey"),
        submitLabel: translate("common.continue", {}, "Continue"),
        name: suggestedPasskeyName(root),
      });
      return;
    }

    const cancelPasskeyNameButton = event.target.closest("[data-passkey-name-cancel]");
    if (cancelPasskeyNameButton) {
      setMessage(root, "", "");
      setPasskeyNameFormState(root, null);
      return;
    }

    const renamePasskeyButton = event.target.closest("[data-passkey-rename]");
    if (renamePasskeyButton) {
      if (!window.PublicKeyCredential || !navigator.credentials) {
        setMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
        return;
      }

      const passkeyId = renamePasskeyButton.getAttribute("data-passkey-rename");
      const currentName = renamePasskeyButton.getAttribute("data-passkey-current-name") || "";
      setMessage(root, "", "");
      setPasskeyNameFormState(root, {
        mode: "rename",
        passkeyId,
        title: translate("settings.rename_this_passkey", {}, "Rename this passkey"),
        submitLabel: translate("settings.save_and_verify", {}, "Save and verify"),
        name: currentName,
      });
      return;
    }

    const deletePasskeyButton = event.target.closest("[data-passkey-delete]");
    if (deletePasskeyButton) {
      if (!window.PublicKeyCredential || !navigator.credentials) {
        setMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
        return;
      }

      setMessage(root, "", "");
      setPasskeyDeleteConfirmState(root, {
        passkeyId: deletePasskeyButton.getAttribute("data-passkey-delete"),
        name:
          deletePasskeyButton.closest(".passkey-row")?.querySelector(".passkey-copy strong")
            ?.textContent?.trim() || translate("settings.delete_target_fallback", {}, "this passkey"),
      });
      return;
    }

    const closeDeletePasskeyButton = event.target.closest("[data-passkey-delete-close]");
    if (closeDeletePasskeyButton) {
      setPasskeyDeleteConfirmState(root, null);
      return;
    }

    const confirmDeletePasskeyButton = event.target.closest("[data-passkey-delete-confirm]");
    if (confirmDeletePasskeyButton) {
      const passkeyId = confirmDeletePasskeyButton.getAttribute("data-passkey-id");
      if (!passkeyId) {
        setPasskeyDeleteConfirmState(root, null);
        setMessage(root, "error", translate("settings.delete_choose_first", {}, "Choose a passkey to delete first."));
        return;
      }

      toggleForms(root, true);
      try {
        await deletePasskey(root, passkeyId);
        setPasskeyDeleteConfirmState(root, null);
        setPasskeyNameFormState(root, null);
        await refresh();
        setMessage(root, "success", translate("settings.deleted_success", {}, "Passkey deleted after confirming another one worked."));
      } catch (error) {
        setMessage(
          root,
          "error",
          error instanceof Error ? error.message : translate("settings.delete_failed", {}, "Could not delete that passkey.")
        );
      } finally {
        toggleForms(root, false);
      }
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }

    const overlay = root.querySelector("[data-passkey-delete-overlay]");
    if (overlay instanceof HTMLElement && !overlay.hidden) {
      setPasskeyDeleteConfirmState(root, null);
    }
  });

  if (passkeyNameForm instanceof HTMLFormElement) {
    passkeyNameForm.addEventListener("submit", async (event) => {
      event.preventDefault();
      const formData = new FormData(passkeyNameForm);
      const passkeyName = String(formData.get("name") || "").trim();
      const mode = passkeyNameForm.dataset.mode;
      const passkeyId = passkeyNameForm.dataset.passkeyId;
      if (!passkeyName) {
        setMessage(root, "error", translate("settings.name_required", {}, "Passkey name is required."));
        const input = root.querySelector("[data-passkey-name-input]");
        if (input instanceof HTMLInputElement) {
          input.focus();
        }
        return;
      }

      toggleForms(root, true);
      try {
        if (mode === "rename") {
          if (!passkeyId) {
            throw new Error(translate("settings.rename_choose_first", {}, "Choose a passkey to rename first."));
          }
          await renamePasskey(root, passkeyId, passkeyName);
        } else {
          await addPasskey(root, passkeyName);
        }
        setPasskeyNameFormState(root, null);
        await refresh();
        setMessage(
          root,
          "success",
          mode === "rename"
            ? translate("settings.renamed_success", {}, "Passkey renamed after confirming it still works.")
            : translate("settings.added_success", {}, "Another passkey is ready to use.")
        );
      } catch (error) {
        setMessage(
          root,
          "error",
          error instanceof Error
            ? error.message
            : mode === "rename"
              ? translate("settings.rename_failed", {}, "Could not rename that passkey.")
              : translate("settings.add_failed", {}, "Could not add another passkey.")
        );
      } finally {
        toggleForms(root, false);
      }
    });
  }

  return refresh();
}

async function addPasskey(root, name) {
  const options = await postJson("/api/v1/auth/passkeys/register/options", { name });
  const credential = await navigator.credentials.create({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson("/api/v1/auth/passkeys/register/verify", {
    credential: credentialToJSON(credential),
  });
}

async function renamePasskey(root, passkeyId, name) {
  const options = await postJson(`/api/v1/auth/passkeys/${passkeyId}/rename/options`, { name });
  const credential = await navigator.credentials.get({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson(`/api/v1/auth/passkeys/${passkeyId}/rename/verify`, {
    credential: credentialToJSON(credential),
  });
}

async function deletePasskey(root, passkeyId) {
  const options = await postJson(`/api/v1/auth/passkeys/${passkeyId}/delete/options`, {});
  const credential = await navigator.credentials.get({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson(`/api/v1/auth/passkeys/${passkeyId}/delete/verify`, {
    credential: credentialToJSON(credential),
  });
}

async function initDashboard() {
  const root = document.querySelector("[data-dashboard]");
  if (!root) {
    return;
  }

  const householdForm = root.querySelector("[data-household-form]");
  const listForm = root.querySelector("[data-list-form]");

  const refresh = async () => {
    setDashboardMessage(root, "", "");
    await loadDashboardData(root);
  };

  root.addEventListener("click", async (event) => {
    const inviteButton = event.target.closest("[data-create-invite]");
    if (inviteButton) {
      const householdId = inviteButton.getAttribute("data-create-invite");
      toggleDashboardForms(root, true);
      try {
        const invite = await postJson(`/api/v1/households/${householdId}/invites`, {});
        const output = root.querySelector(`[data-invite-output="${householdId}"]`);
        const input = root.querySelector(`[data-invite-link-input="${householdId}"]`);
        if (output && input) {
          input.value = invite.invite_url;
          output.hidden = false;
        }
        setDashboardMessage(root, "success", translate("dashboard.invite_link_created", {}, "Invite link created. It stays valid for 24 hours."));
      } catch (error) {
        setDashboardMessage(
          root,
          "error",
          error instanceof Error ? error.message : translate("dashboard.invite_link_create_failed", {}, "Could not create the invite link.")
        );
      } finally {
        toggleDashboardForms(root, false);
      }
      return;
    }

    const copyButton = event.target.closest("[data-copy-invite]");
    if (copyButton) {
      const householdId = copyButton.getAttribute("data-copy-invite");
      const input = root.querySelector(`[data-invite-link-input="${householdId}"]`);
      if (!(input instanceof HTMLInputElement) || !input.value) {
        return;
      }
      try {
        await copyText(input.value);
        setDashboardMessage(root, "success", translate("dashboard.invite_link_copied", {}, "Invite link copied."));
      } catch (error) {
        setDashboardMessage(
          root,
          "error",
          error instanceof Error ? error.message : translate("dashboard.invite_link_copy_failed", {}, "Could not copy the invite link.")
        );
      }
      return;
    }

    const openListButton = event.target.closest("[data-dashboard-open-list]");
    if (openListButton) {
      const listId = openListButton.getAttribute("data-dashboard-open-list");
      if (!listId) {
        setDashboardMessage(root, "error", translate("dashboard.choose_list_before_adding", {}, "Create or choose a list before adding an item."));
        return;
      }

      setDashboardPanelOpen(root, "add", false);
      navigateTo(`/lists/${listId}?addItem=1`);
      return;
    }

    const addOptionButton = event.target.closest("[data-dashboard-add-option]");
    if (addOptionButton) {
      const panelName = addOptionButton.getAttribute("data-dashboard-add-option");
      if (panelName === "household" || panelName === "list") {
        setDashboardPanelOpen(root, panelName, true);
      }
    }
  });

  root.querySelector("[data-dashboard-add-toggle]")?.addEventListener("click", () => {
    const panel = root.querySelector("[data-dashboard-add-panel]");
    setDashboardPanelOpen(root, "add", panel?.hidden ?? true);
  });

  root.querySelectorAll("[data-dashboard-add-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setDashboardPanelOpen(root, "add", false);
    });
  });

  root.querySelectorAll("[data-dashboard-household-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setDashboardPanelOpen(root, "household", false);
    });
  });

  root.querySelectorAll("[data-dashboard-list-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setDashboardPanelOpen(root, "list", false);
    });
  });

  root.querySelectorAll("[data-dashboard-panel-back]").forEach((node) => {
    node.addEventListener("click", () => {
      setDashboardPanelOpen(root, "add", true);
    });
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }

    const panelNames = ["household", "list", "add"];
    const openPanelName = panelNames.find((name) => {
      const panel = root.querySelector(`[data-dashboard-${name}-panel]`);
      return panel instanceof HTMLElement && !panel.hidden;
    });

    if (openPanelName) {
      setDashboardPanelOpen(root, openPanelName, false);
    }
  });

  householdForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(householdForm);
    toggleDashboardForms(root, true);
    try {
      const name = String(formData.get("name") || "").trim();
      if (!name) {
        throw new Error(translate("dashboard.household_name_required", {}, "Please enter a household name."));
      }
      await postJson("/api/v1/households", { name });
      householdForm.reset();
      await refresh();
      setDashboardPanelOpen(root, "household", false);
      setDashboardMessage(root, "success", translate("dashboard.household_created", {}, "Household created. You can add a list now."));
    } catch (error) {
      setDashboardMessage(
        root,
        "error",
        error instanceof Error ? error.message : translate("dashboard.household_create_failed", {}, "Could not create the household.")
      );
    } finally {
      toggleDashboardForms(root, false);
    }
  });

  listForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(listForm);
    toggleDashboardForms(root, true);
    try {
      const householdId = String(formData.get("household_id") || "");
      const name = String(formData.get("name") || "").trim();
      if (!householdId) {
        throw new Error(translate("dashboard.choose_household_before_list", {}, "Create or choose a household before creating a list."));
      }
      if (!name) {
        throw new Error(translate("dashboard.list_name_required", {}, "Please enter a list name."));
      }
      const groceryList = await postJson(`/api/v1/households/${householdId}/lists`, { name });
      listForm.reset();
      await refresh();
      setDashboardPanelOpen(root, "list", false);
      navigateTo(`/lists/${groceryList.id}`);
    } catch (error) {
      setDashboardMessage(
        root,
        "error",
        error instanceof Error ? error.message : translate("dashboard.list_create_failed", {}, "Could not create the list.")
      );
    } finally {
      toggleDashboardForms(root, false);
    }
  });

  try {
    await refresh();
  } catch (error) {
    setDashboardMessage(
      root,
      "error",
      error instanceof Error ? error.message : translate("dashboard.load_failed", {}, "Could not load your households.")
    );
  }
}

function setListMessage(root, type, message, action = null) {
  const errorNode = root.querySelector("[data-list-error]");
  const successNode = root.querySelector("[data-list-success]");

  if (!errorNode || !successNode) {
    return;
  }

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (!message) {
    return;
  }

  const targetNode = type === "error" ? errorNode : successNode;
  targetNode.hidden = false;
  const textNode = document.createElement("span");
  textNode.textContent = message;
  targetNode.appendChild(textNode);
  if (action?.href && action?.label) {
    const actionLink = document.createElement("a");
    actionLink.className = "dashboard-banner-action";
    actionLink.href = action.href;
    actionLink.textContent = action.label;
    targetNode.appendChild(actionLink);
  }
}

function setListSyncStatus(root, message) {
  const statusNode = root.querySelector("[data-list-sync-status]");
  if (statusNode) {
    statusNode.textContent = message;
  }
}

function renderListSwitcher(root, groceryList, householdLists) {
  const switcher = root.querySelector("[data-list-switcher]");
  const select = root.querySelector("[data-list-switcher-select]");
  if (!(switcher instanceof HTMLElement) || !(select instanceof HTMLSelectElement)) {
    return;
  }

  const currentListId = groceryList?.id || root.dataset.listId || "";
  const lists = Array.isArray(householdLists)
    ? householdLists.filter((list) => list?.id && list?.name)
    : [];
  const hasOtherLists = lists.some((list) => list.id !== currentListId);

  select.innerHTML = "";
  switcher.hidden = !hasOtherLists;
  select.disabled = !hasOtherLists;
  const titleHeading = switcher.closest(".list-title-heading");
  if (titleHeading instanceof HTMLElement) {
    titleHeading.classList.toggle("has-switcher", hasOtherLists);
  }
  if (!hasOtherLists) {
    return;
  }

  const groupedLists = new Map();
  lists.forEach((list) => {
    const householdName = list.householdName || "";
    const group = groupedLists.get(householdName) || [];
    group.push(list);
    groupedLists.set(householdName, group);
  });

  groupedLists.forEach((group, householdName) => {
    const parent = householdName ? document.createElement("optgroup") : select;
    if (householdName) {
      parent.label = householdName;
    }
    group.forEach((list) => {
      const option = document.createElement("option");
      option.value = list.id;
      option.textContent = list.name;
      parent.appendChild(option);
    });
    if (parent !== select) {
      select.appendChild(parent);
    }
  });
  select.value = currentListId;
}

async function loadListSwitchTargets() {
  const households = await fetchJson("/api/v1/households");
  const listResponses = await Promise.all(
    households.map(async (household) => ({
      householdName: household.name,
      lists: await fetchJson(`/api/v1/households/${household.id}/lists`),
    }))
  );
  return listResponses.flatMap((response) =>
    response.lists.map((list) => ({
      ...list,
      householdName: response.householdName,
    }))
  );
}

function bindListSwitcher(root) {
  const select = root.querySelector("[data-list-switcher-select]");
  if (!(select instanceof HTMLSelectElement)) {
    return;
  }

  select.addEventListener("change", () => {
    const nextListId = select.value;
    if (!nextListId || nextListId === root.dataset.listId) {
      return;
    }
    navigateTo(`/lists/${nextListId}`);
  });
}

function itemEditHistoryStorageKey(listId) {
  return `planini:item-edit-history:${listId}`;
}

function itemEditRedoHistoryStorageKey(listId) {
  return `planini:item-edit-redo-history:${listId}`;
}

function normalizeNullableItemEditValue(value) {
  const normalized = String(value || "").trim();
  return normalized || null;
}

function normalizeItemEditPayload(payload) {
  return {
    name: String(payload?.name || "").trim(),
    quantity_text: normalizeNullableItemEditValue(payload?.quantity_text),
    note: normalizeNullableItemEditValue(payload?.note),
    category_id: normalizeNullableItemEditValue(payload?.category_id),
  };
}

function itemEditPayloadFromItem(item) {
  return normalizeItemEditPayload({
    name: item?.name,
    quantity_text: item?.quantity_text,
    note: item?.note,
    category_id: item?.category_id,
  });
}

function itemEditPayloadsEqual(left, right) {
  const normalizedLeft = normalizeItemEditPayload(left);
  const normalizedRight = normalizeItemEditPayload(right);
  return (
    normalizedLeft.name === normalizedRight.name &&
    normalizedLeft.quantity_text === normalizedRight.quantity_text &&
    normalizedLeft.note === normalizedRight.note &&
    normalizedLeft.category_id === normalizedRight.category_id
  );
}

function cloneItemEditHistoryItem(item) {
  return item ? { ...item } : null;
}

function loadItemEditHistory(listId) {
  if (typeof window === "undefined" || !listId) {
    return new Map();
  }

  const raw = window.localStorage?.getItem(itemEditHistoryStorageKey(listId));
  if (!raw) {
    return new Map();
  }

  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") {
      return new Map();
    }
    return new Map(
      Object.entries(parsed).map(([itemId, snapshots]) => [
        itemId,
        Array.isArray(snapshots) ? snapshots.slice(0, ITEM_EDIT_HISTORY_LIMIT) : [],
      ]),
    );
  } catch {
    return new Map();
  }
}

function loadItemEditRedoHistory(listId) {
  if (typeof window === "undefined" || !listId) {
    return new Map();
  }

  const raw = window.localStorage?.getItem(itemEditRedoHistoryStorageKey(listId));
  if (!raw) {
    return new Map();
  }

  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") {
      return new Map();
    }
    return new Map(
      Object.entries(parsed).map(([itemId, snapshots]) => [
        itemId,
        Array.isArray(snapshots) ? snapshots.slice(0, ITEM_EDIT_HISTORY_LIMIT) : [],
      ]),
    );
  } catch {
    return new Map();
  }
}

function ensureItemEditHistory(root, state) {
  if (!(state.itemEditHistory instanceof Map)) {
    state.itemEditHistory = loadItemEditHistory(root.dataset.listId || "");
  }
  return state.itemEditHistory;
}

function ensureItemEditRedoHistory(root, state) {
  if (!(state.itemEditRedoHistory instanceof Map)) {
    state.itemEditRedoHistory = loadItemEditRedoHistory(root.dataset.listId || "");
  }
  return state.itemEditRedoHistory;
}

function persistItemEditHistory(root, state) {
  if (typeof window === "undefined" || isDemoList(root)) {
    return;
  }

  const listId = root.dataset.listId;
  if (!listId) {
    return;
  }

  const history = ensureItemEditHistory(root, state);
  const serialized = {};
  history.forEach((snapshots, itemId) => {
    if (snapshots.length > 0) {
      serialized[itemId] = snapshots.slice(0, ITEM_EDIT_HISTORY_LIMIT);
    }
  });
  window.localStorage?.setItem(itemEditHistoryStorageKey(listId), JSON.stringify(serialized));
}

function persistItemEditRedoHistory(root, state) {
  if (typeof window === "undefined" || isDemoList(root)) {
    return;
  }

  const listId = root.dataset.listId;
  if (!listId) {
    return;
  }

  const history = ensureItemEditRedoHistory(root, state);
  const serialized = {};
  history.forEach((snapshots, itemId) => {
    if (snapshots.length > 0) {
      serialized[itemId] = snapshots.slice(0, ITEM_EDIT_HISTORY_LIMIT);
    }
  });
  window.localStorage?.setItem(itemEditRedoHistoryStorageKey(listId), JSON.stringify(serialized));
}

function pushItemEditHistory(root, state, itemId, item) {
  const snapshot = cloneItemEditHistoryItem(item);
  if (!itemId || !snapshot) {
    return;
  }

  const history = ensureItemEditHistory(root, state);
  const snapshots = history.get(itemId) || [];
  if (snapshots[0] && itemEditPayloadsEqual(itemEditPayloadFromItem(snapshots[0]), itemEditPayloadFromItem(snapshot))) {
    return;
  }

  history.set(itemId, [snapshot, ...snapshots].slice(0, ITEM_EDIT_HISTORY_LIMIT));
  persistItemEditHistory(root, state);
}

function pushItemEditRedoHistory(root, state, itemId, item) {
  const snapshot = cloneItemEditHistoryItem(item);
  if (!itemId || !snapshot) {
    return;
  }

  const history = ensureItemEditRedoHistory(root, state);
  const snapshots = history.get(itemId) || [];
  if (snapshots[0] && itemEditPayloadsEqual(itemEditPayloadFromItem(snapshots[0]), itemEditPayloadFromItem(snapshot))) {
    return;
  }

  history.set(itemId, [snapshot, ...snapshots].slice(0, ITEM_EDIT_HISTORY_LIMIT));
  persistItemEditRedoHistory(root, state);
}

function popItemEditHistory(root, state, itemId) {
  const history = ensureItemEditHistory(root, state);
  const snapshots = history.get(itemId) || [];
  const snapshot = snapshots.shift() || null;
  if (snapshots.length > 0) {
    history.set(itemId, snapshots);
  } else {
    history.delete(itemId);
  }
  persistItemEditHistory(root, state);
  return snapshot;
}

function popItemEditRedoHistory(root, state, itemId) {
  const history = ensureItemEditRedoHistory(root, state);
  const snapshots = history.get(itemId) || [];
  const snapshot = snapshots.shift() || null;
  if (snapshots.length > 0) {
    history.set(itemId, snapshots);
  } else {
    history.delete(itemId);
  }
  persistItemEditRedoHistory(root, state);
  return snapshot;
}

function clearItemEditRedoHistory(root, state, itemId) {
  if (!itemId) {
    return;
  }
  const history = ensureItemEditRedoHistory(root, state);
  history.delete(itemId);
  persistItemEditRedoHistory(root, state);
}

function readItemEditFormPayload(root) {
  const form = root.querySelector("[data-item-edit-form]");
  if (!(form instanceof HTMLFormElement)) {
    return null;
  }

  const formData = new FormData(form);
  return normalizeItemEditPayload({
    name: formData.get("name"),
    quantity_text: formData.get("quantity_text"),
    note: formData.get("note"),
    category_id: formData.get("edit_category_id"),
  });
}

function setItemEditFormValues(root, state, item) {
  const form = root.querySelector("[data-item-edit-form]");
  if (!(form instanceof HTMLFormElement)) {
    return;
  }

  const normalized = itemEditPayloadFromItem(item);
  form.elements.namedItem("name").value = normalized.name;
  form.elements.namedItem("quantity_text").value = normalized.quantity_text || "";
  form.elements.namedItem("note").value = normalized.note || "";
  setCategoryRadioValue(root, 'input[name="edit_category_id"]', normalized.category_id || "");
  syncCategoryRadioGroups(root, state);
}

function setItemEditStatus(root, status, message) {
  const statusNode = root.querySelector("[data-item-edit-status]");
  const textNode = root.querySelector("[data-item-edit-status-text]");
  const spinner = root.querySelector("[data-item-edit-spinner]");
  if (!statusNode || !textNode) {
    return;
  }

  statusNode.hidden = !message;
  statusNode.dataset.status = status || "";
  statusNode.classList.toggle("is-saving", status === "saving");
  statusNode.classList.toggle("is-error", status === "error");
  statusNode.classList.toggle("is-saved", status === "saved");
  textNode.textContent = message || "";
  if (spinner instanceof HTMLElement) {
    spinner.hidden = status !== "saving";
  }
}

function isItemEditDraftDirty(root, state) {
  const payload = readItemEditFormPayload(root);
  if (!payload || !state.itemEditLastSavedPayload) {
    return false;
  }
  return !itemEditPayloadsEqual(payload, state.itemEditLastSavedPayload);
}

function updateItemEditUndoButton(root, state) {
  const undoButton = root.querySelector("[data-item-edit-undo]");
  const redoButton = root.querySelector("[data-item-edit-redo]");
  if (!undoButton && !redoButton) {
    return;
  }

  const itemId = state.editingItemId;
  const history = itemId ? ensureItemEditHistory(root, state).get(itemId) || [] : [];
  const redoHistory = itemId ? ensureItemEditRedoHistory(root, state).get(itemId) || [] : [];
  if (undoButton) {
    undoButton.disabled = Boolean(state.itemEditSaveInFlight) || (!isItemEditDraftDirty(root, state) && history.length === 0);
  }
  if (redoButton) {
    redoButton.disabled = Boolean(state.itemEditSaveInFlight) || redoHistory.length === 0;
  }
}

function cancelItemEditSaveTimer(state) {
  if (state.itemEditSaveTimerId && typeof window !== "undefined") {
    window.clearTimeout(state.itemEditSaveTimerId);
  }
  state.itemEditSaveTimerId = null;
}

async function applyItemEditPayload(root, state, itemId, payload, { recordHistory = true } = {}) {
  const normalized = normalizeItemEditPayload(payload);
  if (!normalized.name) {
    setItemEditStatus(root, "error", translate("list_detail.item_name_required", {}, "Please enter an item name."));
    setListMessage(root, "error", translate("list_detail.item_name_required", {}, "Please enter an item name."));
    updateItemEditUndoButton(root, state);
    return false;
  }

  const previousItem = state.items.get(itemId);
  if (!previousItem) {
    const message = translate("list_detail.item_not_found", {}, "Could not find that item.");
    setItemEditStatus(root, "error", message);
    setListMessage(root, "error", message);
    updateItemEditUndoButton(root, state);
    return false;
  }

  if (itemEditPayloadsEqual(itemEditPayloadFromItem(previousItem), normalized)) {
    state.itemEditLastSavedPayload = itemEditPayloadFromItem(previousItem);
    updateItemEditUndoButton(root, state);
    return true;
  }

  setItemEditStatus(root, "saving", translate("list_detail.item_saving", {}, "Saving..."));
  try {
    const updatedItem = await updateItemWithOfflineFallback(root, state, itemId, normalized);
    if (recordHistory) {
      pushItemEditHistory(root, state, itemId, previousItem);
      clearItemEditRedoHistory(root, state, itemId);
    }
    upsertItem(state, updatedItem);
    state.itemEditLastSavedPayload = itemEditPayloadFromItem(updatedItem);
    renderItems(root, state);
    persistOfflineListState(root, state);
    if (state.pendingMutations.length > 0) {
      showOfflineSavedMessage(root);
    }
    setItemEditStatus(root, "saved", translate("list_detail.item_saved", {}, "Saved."));
    updateItemEditUndoButton(root, state);
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : translate("list_detail.item_update_failed", {}, "Could not save item.");
    setItemEditStatus(root, "error", message);
    setListMessage(root, "error", message);
    updateItemEditUndoButton(root, state);
    return false;
  }
}

async function saveItemEditDraft(root, state) {
  cancelItemEditSaveTimer(state);
  if (state.itemEditSaveInFlight) {
    state.itemEditNeedsSave = true;
    return state.itemEditSaveInFlight;
  }

  state.itemEditNeedsSave = false;
  state.itemEditSaveInFlight = (async () => {
    let saved = true;
    do {
      state.itemEditNeedsSave = false;
      const itemId = state.editingItemId;
      const payload = readItemEditFormPayload(root);
      if (!itemId || !payload) {
        return saved;
      }
      saved = (await applyItemEditPayload(root, state, itemId, payload)) && saved;
    } while (state.itemEditNeedsSave);
    return saved;
  })();

  try {
    return await state.itemEditSaveInFlight;
  } finally {
    state.itemEditSaveInFlight = null;
    updateItemEditUndoButton(root, state);
  }
}

function scheduleItemEditSave(root, state, delayMs = ITEM_EDIT_LIVE_SAVE_DELAY_MS) {
  if (!state.editingItemId) {
    return;
  }

  cancelItemEditSaveTimer(state);
  state.itemEditSaveTimerId = window.setTimeout(() => {
    state.itemEditSaveTimerId = null;
    void saveItemEditDraft(root, state);
  }, delayMs);
  updateItemEditUndoButton(root, state);
}

async function flushItemEditSave(root, state) {
  cancelItemEditSaveTimer(state);
  return saveItemEditDraft(root, state);
}

async function closeItemEditPanel(root, state) {
  const saved = await flushItemEditSave(root, state);
  if (!saved) {
    return false;
  }
  setItemEditPanelOpen(root, state, null);
  return true;
}

async function undoItemEdit(root, state) {
  const itemId = state.editingItemId;
  if (!itemId) {
    return false;
  }

  cancelItemEditSaveTimer(state);
  if (state.itemEditSaveInFlight) {
    await state.itemEditSaveInFlight;
  }

  const currentItem = state.items.get(itemId);
  const currentPayload = currentItem ? itemEditPayloadFromItem(currentItem) : null;
  const draftPayload = readItemEditFormPayload(root);
  if (currentPayload && draftPayload && !itemEditPayloadsEqual(currentPayload, draftPayload)) {
    pushItemEditRedoHistory(root, state, itemId, { ...currentItem, ...draftPayload });
    setItemEditFormValues(root, state, currentItem);
    state.itemEditLastSavedPayload = currentPayload;
    setItemEditStatus(root, "saved", translate("list_detail.item_saved", {}, "Saved."));
    updateItemEditUndoButton(root, state);
    return true;
  }

  const previousItem = popItemEditHistory(root, state, itemId);
  if (!previousItem) {
    setItemEditStatus(root, "error", translate("list_detail.item_edit_undo_empty", {}, "No edits to undo."));
    updateItemEditUndoButton(root, state);
    return false;
  }

  const restored = await applyItemEditPayload(
    root,
    state,
    itemId,
    itemEditPayloadFromItem(previousItem),
    { recordHistory: false },
  );
  if (restored) {
    const nextItem = state.items.get(itemId);
    if (nextItem) {
      setItemEditFormValues(root, state, nextItem);
    }
    if (currentItem) {
      pushItemEditRedoHistory(root, state, itemId, currentItem);
    }
    setListMessage(root, "success", translate("list_detail.item_edit_undone", {}, "Edit undone."));
  } else {
    pushItemEditHistory(root, state, itemId, previousItem);
  }
  updateItemEditUndoButton(root, state);
  return restored;
}

async function redoItemEdit(root, state) {
  const itemId = state.editingItemId;
  if (!itemId) {
    return false;
  }

  cancelItemEditSaveTimer(state);
  if (state.itemEditSaveInFlight) {
    await state.itemEditSaveInFlight;
  }

  const nextItem = popItemEditRedoHistory(root, state, itemId);
  if (!nextItem) {
    setItemEditStatus(root, "error", translate("list_detail.item_edit_redo_empty", {}, "No edits to redo."));
    updateItemEditUndoButton(root, state);
    return false;
  }

  const currentItem = state.items.get(itemId);
  const restored = await applyItemEditPayload(
    root,
    state,
    itemId,
    itemEditPayloadFromItem(nextItem),
    { recordHistory: false },
  );
  if (restored) {
    const updatedItem = state.items.get(itemId);
    if (updatedItem) {
      setItemEditFormValues(root, state, updatedItem);
    }
    if (currentItem) {
      pushItemEditHistory(root, state, itemId, currentItem);
    }
    setListMessage(root, "success", translate("list_detail.item_edit_redone", {}, "Edit redone."));
  } else {
    pushItemEditRedoHistory(root, state, itemId, nextItem);
  }
  updateItemEditUndoButton(root, state);
  return restored;
}

function offlineListStorageKey(listId) {
  return `${OFFLINE_LIST_STORAGE_PREFIX}${listId}`;
}

function loadOfflineListState(listId) {
  if (typeof window === "undefined" || !listId) {
    return null;
  }

  const raw = window.localStorage?.getItem(offlineListStorageKey(listId));
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

function createOfflineId(prefix) {
  return `${prefix}${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function isBrowserOffline() {
  return typeof navigator !== "undefined" && navigator.onLine === false;
}

function isOfflineRequestError(error) {
  return isBrowserOffline() || error instanceof TypeError;
}

function listTitleText(root) {
  return root.querySelector("[data-list-title]")?.textContent?.trim() || "";
}

function setListName(root, state, name) {
  state.listName = name;
  root.querySelector("[data-list-title]").textContent = name;
  root.querySelector("[data-list-name-input]").value = name;
}

async function saveListName(root, state, name) {
  const trimmedName = name.trim();
  if (!trimmedName) {
    throw new Error(translate("list_detail.list_name_required", {}, "Please enter a list name."));
  }

  if (isDemoList(root)) {
    state.demoPayload.list.name = trimmedName;
    root.dataset.demoPayload = JSON.stringify(state.demoPayload);
    setListName(root, state, trimmedName);
    return state.demoPayload.list;
  }

  const listId = root.dataset.listId;
  const groceryList = await fetchJson(`/api/v1/lists/${listId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: trimmedName }),
  });
  setListName(root, state, groceryList.name);
  persistOfflineListState(root, state);
  return groceryList;
}

function persistOfflineListState(root, state) {
  if (typeof window === "undefined" || isDemoList(root)) {
    return;
  }

  const listId = root.dataset.listId;
  if (!listId) {
    return;
  }

  window.localStorage?.setItem(
    offlineListStorageKey(listId),
    JSON.stringify({
      title: listTitleText(root),
      items: [...state.items.values()],
      lists: state.lists || [],
      checkedRemainingCount: state.checkedRemainingCount || 0,
      categories: [...state.categories.values()],
      categoryOrder: [...state.categoryOrder.entries()].map(([category_id, sort_order]) => ({
        category_id,
        sort_order,
      })),
      disabledCategoryIds: getDisabledCategoryIds(state),
      pendingMutations: state.pendingMutations || [],
    }),
  );
}

function applyOfflineListState(root, state, cachedState) {
  setListName(root, state, cachedState.title || listTitleText(root));

  state.categories = new Map((cachedState.categories || []).map((category) => [category.id, category]));
  state.lists = cachedState.lists || [];
  state.categoryOrder = new Map(
    (cachedState.categoryOrder || []).map((entry) => [entry.category_id, entry.sort_order]),
  );
  setDisabledCategoryIds(state, cachedState.disabledCategoryIds || []);
  replaceItems(state, cachedState.items || []);
  state.checkedRemainingCount = cachedState.checkedRemainingCount || 0;
  state.pendingMutations = cachedState.pendingMutations || [];
  syncCategoryRadioGroups(root, state);
  renderItems(root, state);
}

function showOfflineSavedMessage(root) {
  setListMessage(
    root,
    "error",
    translate(
      "list_detail.offline_saved_local",
      {},
      "Offline. Changes saved locally and will sync when connection returns.",
    ),
  );
  setListSyncStatus(
    root,
    translate("list_detail.offline_sync_pending", {}, "Changes saved locally."),
  );
}

function queueOfflineMutation(root, state, mutation, applyLocalChange) {
  const result = applyLocalChange();
  state.pendingMutations.push(mutation);
  persistOfflineListState(root, state);
  showOfflineSavedMessage(root);
  return result;
}

function shouldQueueItemMutation(state, itemId = "") {
  return Boolean(
    state.pendingMutations.length > 0 ||
      isBrowserOffline() ||
      String(itemId).startsWith(OFFLINE_ITEM_ID_PREFIX),
  );
}

function applyOfflineSyncResult(state, result) {
  Object.entries(result.client_item_ids || {}).forEach(([localId, serverId]) => {
    const localItem = state.items.get(localId);
    if (localItem) {
      state.items.delete(localId);
      state.items.set(serverId, { ...localItem, id: serverId });
    }
  });

  (result.deleted_item_ids || []).forEach((itemId) => {
    removeItem(state, itemId);
  });

  (result.items || []).forEach((item) => {
    upsertItem(state, item);
  });

  const appliedMutationIds = new Set(result.applied_mutation_ids || []);
  state.pendingMutations = state.pendingMutations.filter(
    (mutation) => !appliedMutationIds.has(mutation.mutation_id),
  );
}

async function flushOfflineMutations(root, state) {
  if (isDemoList(root) || state.pendingMutations.length === 0) {
    return null;
  }

  if (state.offlineSyncInFlight) {
    return state.offlineSyncInFlight;
  }

  const listId = root.dataset.listId;
  const mutations = [...state.pendingMutations];
  setListSyncStatus(root, translate("list_detail.offline_syncing", {}, "Syncing saved changes..."));
  state.offlineSyncInFlight = postJson(`/api/v1/lists/${listId}/items/sync`, { mutations })
    .then((result) => {
      applyOfflineSyncResult(state, result);
      persistOfflineListState(root, state);
      renderItems(root, state);
      if (state.pendingMutations.length === 0) {
        setListMessage(
          root,
          "success",
          translate("list_detail.offline_synced", {}, "Saved offline changes synced."),
        );
        setListSyncStatus(root, translate("list_detail.sync_on", {}, "Live updates on."));
      } else {
        showOfflineSavedMessage(root);
      }
      return result;
    })
    .catch((error) => {
      if (isOfflineRequestError(error)) {
        showOfflineSavedMessage(root);
        return null;
      }
      setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.list_action_failed", {}, "List action failed."));
      return null;
    })
    .finally(() => {
      state.offlineSyncInFlight = null;
    });
  return state.offlineSyncInFlight;
}

function hideUndoToast(root, state) {
  const toast = root.querySelector("[data-list-toast]");
  const message = root.querySelector("[data-list-toast-message]");
  const timer = root.querySelector("[data-list-toast-timer]");
  if (!toast || !message) {
    return;
  }

  if (state.undoTimerId) {
    window.clearTimeout(state.undoTimerId);
  }
  state.undoTimerId = null;
  state.undoAction = null;
  message.textContent = "";
  if (timer instanceof HTMLElement) {
    timer.style.animation = "none";
  }
  toast.classList.remove("is-active");
  toast.hidden = true;
}

function showUndoToast(root, state, messageText, undoAction) {
  const toast = root.querySelector("[data-list-toast]");
  const message = root.querySelector("[data-list-toast-message]");
  const timer = root.querySelector("[data-list-toast-timer]");
  if (!toast || !message) {
    return;
  }

  hideUndoToast(root, state);
  state.undoAction = undoAction;
  message.textContent = messageText;
  toast.hidden = false;
  if (timer instanceof HTMLElement) {
    timer.style.animation = "none";
    // Force a reflow so the countdown animation reliably restarts each time.
    void timer.offsetWidth;
    timer.style.animation = "";
  }
  toast.classList.add("is-active");
  state.undoTimerId = window.setTimeout(() => {
    hideUndoToast(root, state);
  }, UNDO_ACTION_DURATION_MS);
}

async function runUndoAction(root, state, undoAction) {
  try {
    await undoAction();
  } catch (error) {
    setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.undo_failed", {}, "Could not undo action."));
  }
}

function clearMovedItemNoticeTimers(notice) {
  if (!notice) {
    return;
  }
  if (notice.timerId) {
    window.clearTimeout(notice.timerId);
  }
  if (notice.removalTimerId) {
    window.clearTimeout(notice.removalTimerId);
  }
  notice.timerId = null;
  notice.removalTimerId = null;
}

function movedItemNoticeRenderItem(notice) {
  return {
    id: `moved-notice-${notice.id}`,
    name: notice.itemName,
    category_id: notice.categoryId || null,
    checked: Boolean(notice.checked),
    checked_at: notice.checkedAt || null,
    hidden_until: null,
    sort_order: notice.sortOrder || 0,
    movedNotice: notice,
  };
}

function dismissMovedItemNotice(root, state, itemId, animate = true) {
  const notice = state.movedItemNotices?.get(itemId);
  if (!notice) {
    return;
  }

  clearMovedItemNoticeTimers(notice);
  if (!animate) {
    state.movedItemNotices.delete(itemId);
    renderItems(root, state);
    return;
  }

  notice.isExpiring = true;
  const noticeNode = root.querySelector(`[data-moved-item-notice="${itemId}"]`);
  if (noticeNode instanceof HTMLElement) {
    noticeNode.classList.add("is-expiring");
  }
  notice.removalTimerId = window.setTimeout(() => {
    state.movedItemNotices.delete(itemId);
    renderItems(root, state);
  }, MOVED_ITEM_NOTICE_FADE_MS);
}

function scheduleMovedItemNoticeDismiss(root, state, notice) {
  clearMovedItemNoticeTimers(notice);
  notice.timerId = window.setTimeout(() => {
    dismissMovedItemNotice(root, state, notice.id, true);
  }, UNDO_ACTION_DURATION_MS);
}

function movedItemNoticeTargetName(state, targetListId) {
  return state.lists?.find((list) => list.id === targetListId)?.name || translate("list_detail.another_list", {}, "another list");
}

function createMovedItemNotice(root, state, sourceItem, movedItem, targetListId) {
  const sourceListId = sourceItem.list_id || root.dataset.listId || "";
  return {
    id: movedItem.id,
    sourceListId,
    targetListId,
    targetListName: movedItemNoticeTargetName(state, targetListId),
    itemName: movedItem.name || sourceItem.name,
    categoryId: sourceItem.category_id || null,
    checked: Boolean(sourceItem.checked),
    checkedAt: sourceItem.checked_at || null,
    sortOrder: sourceItem.sort_order || 0,
    restorePayload: {
      name: movedItem.name || sourceItem.name,
      quantity_text: movedItem.quantity_text || null,
      note: movedItem.note || null,
      category_id: movedItem.category_id || null,
      list_id: sourceListId,
    },
  };
}

function showMovedItemNotice(root, state, notice) {
  if (!state.movedItemNotices) {
    state.movedItemNotices = new Map();
  }
  const existingNotice = state.movedItemNotices.get(notice.id);
  clearMovedItemNoticeTimers(existingNotice);
  state.movedItemNotices.set(notice.id, {
    ...notice,
    isExpiring: false,
    timerId: null,
    removalTimerId: null,
  });
  renderItems(root, state);

  const activeNotice = state.movedItemNotices.get(notice.id);
  if (activeNotice) {
    scheduleMovedItemNoticeDismiss(root, state, activeNotice);
  }

  const noticeNode = root.querySelector(`[data-moved-item-notice="${notice.id}"]`);
  if (noticeNode instanceof HTMLElement && typeof noticeNode.scrollIntoView === "function") {
    noticeNode.scrollIntoView({ behavior: "smooth", block: "center" });
  }
}

async function restoreMovedItem(root, state, itemId) {
  const notice = state.movedItemNotices?.get(itemId);
  if (!notice) {
    throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
  }

  clearMovedItemNoticeTimers(notice);
  try {
    const restoredItem = await moveItemWithOfflineFallback(root, state, itemId, notice.restorePayload);
    state.movedItemNotices.delete(itemId);
    upsertItem(state, restoredItem);
    renderItems(root, state);
    persistOfflineListState(root, state);
    setListMessage(
      root,
      "success",
      translate("list_detail.item_move_undone_named", { name: restoredItem.name }, "{name} moved back.")
    );
    highlightItem(root, state, restoredItem.id);
    return restoredItem;
  } catch (error) {
    scheduleMovedItemNoticeDismiss(root, state, notice);
    throw error;
  }
}

function normalizeItemName(value) {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function normalizeSearchText(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function boundedEditDistance(left, right, maxDistance) {
  if (Math.abs(left.length - right.length) > maxDistance) {
    return maxDistance + 1;
  }

  let previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const current = [leftIndex];
    let rowBest = current[0];
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const substitutionCost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1;
      const value = Math.min(
        previous[rightIndex] + 1,
        current[rightIndex - 1] + 1,
        previous[rightIndex - 1] + substitutionCost
      );
      current[rightIndex] = value;
      rowBest = Math.min(rowBest, value);
    }
    if (rowBest > maxDistance) {
      return maxDistance + 1;
    }
    previous = current;
  }
  return previous[right.length];
}

function fuzzyItemNameDistance(itemName, query) {
  if (query.length < 3) {
    return null;
  }

  const maxDistance = query.length <= 4 ? 1 : 2;
  let bestDistance = boundedEditDistance(itemName, query, maxDistance);
  const minWindowLength = Math.max(1, query.length - maxDistance);
  const maxWindowLength = Math.min(itemName.length, query.length + maxDistance);

  for (let startIndex = 0; startIndex < itemName.length; startIndex += 1) {
    for (let windowLength = minWindowLength; windowLength <= maxWindowLength; windowLength += 1) {
      const candidate = itemName.slice(startIndex, startIndex + windowLength);
      if (candidate.length < minWindowLength) {
        continue;
      }
      bestDistance = Math.min(bestDistance, boundedEditDistance(candidate, query, maxDistance));
      if (bestDistance === 0) {
        return bestDistance;
      }
    }
  }

  return bestDistance <= maxDistance ? bestDistance : null;
}

function itemSuggestionMatch(itemName, query) {
  const normalizedName = normalizeSearchText(itemName);
  const normalizedQuery = normalizeSearchText(query);
  if (normalizedName === normalizedQuery) {
    return { distance: 0, rank: 0 };
  }
  if (normalizedName.startsWith(normalizedQuery)) {
    return { distance: 0, rank: 1 };
  }
  if (normalizedName.includes(normalizedQuery)) {
    return { distance: 0, rank: 2 };
  }

  const distance = fuzzyItemNameDistance(normalizedName, normalizedQuery);
  return distance === null ? null : { distance, rank: 3 };
}

function syncModalState(root) {
  const addOverlay = root.querySelector("[data-item-panel-overlay]");
  const editOverlay = root.querySelector("[data-item-edit-overlay]");
  const settingsOverlay = root.querySelector("[data-list-settings-overlay]");
  const categoryConfirmOverlay = root.querySelector("[data-category-disable-confirm-overlay]");
  const hasModalOpen =
    (addOverlay instanceof HTMLElement && !addOverlay.hidden) ||
    (editOverlay instanceof HTMLElement && !editOverlay.hidden) ||
    (settingsOverlay instanceof HTMLElement && !settingsOverlay.hidden) ||
    (categoryConfirmOverlay instanceof HTMLElement && !categoryConfirmOverlay.hidden);

  root.classList.toggle("has-modal-open", hasModalOpen);
  document.body.classList.toggle("has-list-modal-open", hasModalOpen);
}

function setItemPanelOpen(root, isOpen) {
  const panel = root.querySelector("[data-item-panel]");
  const overlay = root.querySelector("[data-item-panel-overlay]");
  const toggles = root.querySelectorAll("[data-item-form-toggle]");
  const nameInput = root.querySelector("[data-item-name-input]");
  const categorySearch = root.querySelector("[data-item-category-search]");
  const editPanel = root.querySelector("[data-item-edit-panel]");
  const editOverlay = root.querySelector("[data-item-edit-overlay]");
  const settingsPanel = root.querySelector("[data-list-settings-panel]");
  const settingsOverlay = root.querySelector("[data-list-settings-overlay]");

  if (!panel || !overlay || toggles.length === 0) {
    return;
  }

  if (
    !isOpen &&
    document.activeElement instanceof HTMLElement &&
    panel.contains(document.activeElement)
  ) {
    document.activeElement.blur();
  }

  overlay.hidden = !isOpen;
  panel.hidden = !isOpen;
  if (isOpen && editPanel instanceof HTMLElement && editOverlay instanceof HTMLElement) {
    editPanel.hidden = true;
    editOverlay.hidden = true;
  }
  if (isOpen && settingsPanel instanceof HTMLElement && settingsOverlay instanceof HTMLElement) {
    settingsPanel.hidden = true;
    settingsOverlay.hidden = true;
  }
  if (isOpen && categorySearch instanceof HTMLInputElement) {
    categorySearch.value = "";
  }
  toggles.forEach((toggle) => {
    toggle.setAttribute("aria-expanded", String(isOpen));
  });
  syncModalState(root);

  if (isOpen && nameInput instanceof HTMLElement) {
    window.setTimeout(() => {
      nameInput.focus();
    }, 0);
  }
}

function openItemPanelForCategory(root, state, categoryId) {
  const selectedCategoryId = categoryId && state.categories.has(categoryId) ? categoryId : "";
  const categorySearch = root.querySelector("[data-item-category-search]");
  if (categorySearch instanceof HTMLInputElement) {
    categorySearch.value = "";
  }
  setItemPanelOpen(root, true);
  syncCategoryRadioGroups(root, state);
  setCategoryRadioValue(root, 'input[name="category_id"]', selectedCategoryId);
  renderItemSuggestions(root, state);
}

function formatSuggestionMeta(state, item) {
  const meta = [];
  const category = item.category_id ? state.categories.get(item.category_id)?.name || "" : "";
  if (category) {
    meta.push(category);
  }
  if (item.quantity_text) {
    meta.push(item.quantity_text);
  }
  if (item.note) {
    meta.push(item.note);
  }
  meta.push(item.checked
    ? translate("list_detail.checked_earlier", {}, "checked earlier")
    : translate("list_detail.already_on_list", {}, "already on this list"));
  return meta.join(" / ");
}

function categorySortKey(state, categoryId) {
  if (!categoryId) {
    return {
      color: "",
      name: translate("list_detail.uncategorized", {}, "Uncategorized"),
      isExplicit: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
    };
  }

  const category = state.categories.get(categoryId);
  if (!category) {
    return {
      color: "",
      name: translate("list_detail.uncategorized", {}, "Uncategorized"),
      isExplicit: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
    };
  }

  return {
    color: category.color || "",
    name: category.name,
    isExplicit: state.categoryOrder.has(categoryId),
    sortOrder: state.categoryOrder.get(categoryId) ?? Number.MAX_SAFE_INTEGER,
  };
}

function decorateItem(state, item) {
  const category = item.category_id ? state.categories.get(item.category_id) : null;
  return {
    ...item,
    _categoryColor: category?.color || "",
    _categoryName: category?.name || "",
  };
}

function setCategoryRadioValue(root, selector, categoryId) {
  root.querySelectorAll(selector).forEach((radio) => {
    if (!(radio instanceof HTMLInputElement)) {
      return;
    }

    radio.checked = radio.value === (categoryId || "");
  });
}

function categoryMatchesQuery(category, query) {
  if (!query) {
    return true;
  }

  const haystacks = [category.name, ...(category.aliases || [])].map((value) => normalizeSearchText(value));
  return haystacks.some((value) => value.includes(query));
}

function setDisabledCategoryIds(state, categoryIds) {
  state.disabledCategoryIds = new Set(categoryIds || []);
}

function getDisabledCategoryIds(state) {
  return [...(state.disabledCategoryIds || new Set())]
    .filter((categoryId) => state.categories.has(categoryId))
    .sort((leftId, rightId) => {
      const leftName = state.categories.get(leftId)?.name || "";
      const rightName = state.categories.get(rightId)?.name || "";
      return leftName.localeCompare(rightName);
    });
}

function isCategoryDisabled(state, categoryId) {
  return Boolean(categoryId && state.disabledCategoryIds?.has(categoryId));
}

function syncCategoryRadioGroup(container, groupName, currentValue, state, searchQuery) {
  if (!(container instanceof HTMLElement)) {
    return;
  }

  container.innerHTML = "";
  const effectiveCurrentValue = isCategoryDisabled(state, currentValue) ? "" : currentValue;
  const categories = [...state.categories.values()].sort((left, right) => left.name.localeCompare(right.name));
  const options = [
    {
      color: "",
      id: "",
      name: translate("list_detail.no_category", {}, "No category"),
      hint: translate("list_detail.no_category_hint", {}, "Keep this item above the category sections."),
    },
    ...categories,
  ].filter(
    (category, index) =>
      index === 0 ||
      (!isCategoryDisabled(state, category.id) &&
        (category.id === (effectiveCurrentValue || "") || categoryMatchesQuery(category, searchQuery)))
  );

  options.forEach((category, index) => {
    const option = document.createElement("label");
    option.className = "category-radio-option";

    const input = document.createElement("input");
    input.type = "radio";
    input.name = groupName;
    input.value = category.id;
    input.checked = (effectiveCurrentValue || "") === category.id;
    option.appendChild(input);

    const card = document.createElement("span");
    card.className = "category-radio-card";

    const swatch = document.createElement("span");
    swatch.className = "category-radio-swatch";
    swatch.style.background = category.color || CATEGORY_SWATCH_FALLBACK_COLOR;
    card.appendChild(swatch);

    const copy = document.createElement("span");
    copy.className = "category-radio-copy";

    const title = document.createElement("strong");
    title.textContent = category.name;
    copy.appendChild(title);

    if (index === 0) {
      const hint = document.createElement("span");
      hint.textContent = category.hint;
      copy.appendChild(hint);
    }

    card.appendChild(copy);
    option.appendChild(card);
    container.appendChild(option);
  });
}

function syncCategoryRadioGroups(root, state) {
  const addContainer = root.querySelector("[data-item-category-radios]");
  const editContainer = root.querySelector("[data-item-edit-category-radios]");
  const addSearchInput = root.querySelector("[data-item-category-search]");
  const editSearchInput = root.querySelector("[data-item-edit-category-search]");
  const addSearch = addSearchInput instanceof HTMLInputElement ? addSearchInput.value : "";
  const editSearch = editSearchInput instanceof HTMLInputElement ? editSearchInput.value : "";
  const addCurrentValue =
    root.querySelector('input[name="category_id"]:checked') instanceof HTMLInputElement
      ? root.querySelector('input[name="category_id"]:checked').value
      : "";
  const editCurrentValue =
    root.querySelector('input[name="edit_category_id"]:checked') instanceof HTMLInputElement
      ? root.querySelector('input[name="edit_category_id"]:checked').value
      : "";

  syncCategoryRadioGroup(
    addContainer,
    "category_id",
    addCurrentValue,
    state,
    normalizeSearchText(addSearch)
  );
  syncCategoryRadioGroup(
    editContainer,
    "edit_category_id",
    editCurrentValue,
    state,
    normalizeSearchText(editSearch)
  );
}

function getManualCategoryIds(state) {
  return [...state.categories.values()]
    .filter((category) => state.categoryOrder.has(category.id))
    .sort((left, right) => state.categoryOrder.get(left.id) - state.categoryOrder.get(right.id))
    .map((category) => category.id);
}

function getAlphabeticalCategoryIds(state) {
  return [...state.categories.values()]
    .filter((category) => !state.categoryOrder.has(category.id))
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((category) => category.id);
}

function getOrderedCategoryIds(state) {
  return [...getManualCategoryIds(state), ...getAlphabeticalCategoryIds(state)];
}

function getDisplayedCategoryIds(state) {
  const itemCategoryIds = new Set(
    [...state.items.values()]
      .filter((item) => !item.checked && !isItemHidden(item))
      .map((item) => item.category_id)
      .filter((categoryId) => categoryId && state.categories.has(categoryId))
  );

  return getOrderedCategoryIds(state).filter((categoryId) => itemCategoryIds.has(categoryId));
}

function deriveManualCategoryIds(state, orderedCategoryIds) {
  for (let prefixLength = 0; prefixLength <= orderedCategoryIds.length; prefixLength += 1) {
    const prefix = orderedCategoryIds.slice(0, prefixLength);
    const remainder = orderedCategoryIds.slice(prefixLength);
    const alphabeticalRemainder = [...remainder].sort((leftId, rightId) => {
      const leftName = state.categories.get(leftId)?.name || "";
      const rightName = state.categories.get(rightId)?.name || "";
      return leftName.localeCompare(rightName);
    });

    if (
      remainder.length === alphabeticalRemainder.length &&
      remainder.every((categoryId, index) => categoryId === alphabeticalRemainder[index])
    ) {
      return prefix;
    }
  }
}

function setCategoryOrder(state, categoryIds) {
  state.categoryOrder = new Map(categoryIds.map((categoryId, index) => [categoryId, index]));
}

function reorderCategoryIds(categoryIds, categoryId, nextIndex) {
  const currentIndex = categoryIds.indexOf(categoryId);
  if (currentIndex === -1 || nextIndex < 0 || nextIndex >= categoryIds.length) {
    return categoryIds;
  }

  const nextCategoryIds = [...categoryIds];
  const [movedCategoryId] = nextCategoryIds.splice(currentIndex, 1);
  nextCategoryIds.splice(nextIndex, 0, movedCategoryId);
  return nextCategoryIds;
}

function categoryIdsEqual(leftCategoryIds, rightCategoryIds) {
  return (
    leftCategoryIds.length === rightCategoryIds.length &&
    leftCategoryIds.every((categoryId, index) => categoryId === rightCategoryIds[index])
  );
}

function isDemoList(root) {
  return root.dataset.listMode === "demo";
}

function getDemoPayload(root) {
  if (!isDemoList(root)) {
    return null;
  }

  try {
    return JSON.parse(root.dataset.demoPayload || "{}");
  } catch {
    return null;
  }
}

function cloneDemoItem(item) {
  return {
    id: item.id,
    list_id: item.list_id || null,
    name: item.name,
    category_id: item.category_id || null,
    quantity_text: item.quantity_text || null,
    note: item.note || null,
    checked: Boolean(item.checked),
    checked_at: item.checked_at || null,
    checked_state_recorded_at: item.checked_state_recorded_at || item.checked_at || null,
    hidden_until: item.hidden_until || null,
    sort_order: Number(item.sort_order || 0),
  };
}

function getNextDemoSortOrder(state) {
  return [...state.items.values()].reduce((highest, item) => Math.max(highest, item.sort_order), -1) + 1;
}

function createDemoItem(state, payload) {
  const item = cloneDemoItem({
    id: `demo-item-${state.nextDemoId}`,
    list_id: payload.list_id || null,
    name: payload.name,
    category_id: payload.category_id || null,
    quantity_text: payload.quantity_text || null,
    note: payload.note || null,
    checked: false,
    checked_at: null,
    sort_order: payload.sort_order ?? getNextDemoSortOrder(state),
  });
  state.nextDemoId += 1;
  return item;
}

function updateDemoItem(state, itemId, payload) {
  const existingItem = state.items.get(itemId);
  if (!existingItem) {
    throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
  }

  return cloneDemoItem({
    ...existingItem,
    ...payload,
  });
}

function setDemoItemChecked(state, itemId, checked) {
  const existingItem = state.items.get(itemId);
  if (!existingItem) {
    throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
  }

  return cloneDemoItem({
    ...existingItem,
    checked,
    checked_at: checked ? new Date().toISOString() : null,
  });
}

function createOfflineItem(state, listId, clientItemId, payload, recordedAt) {
  return {
    id: clientItemId,
    list_id: listId,
    name: payload.name,
    category_id: payload.category_id || null,
    quantity_text: payload.quantity_text || null,
    note: payload.note || null,
    checked: false,
    checked_at: null,
    checked_state_recorded_at: recordedAt,
    hidden_until: null,
    sort_order: payload.sort_order ?? getNextDemoSortOrder(state),
  };
}

function applyLocalCheckedState(item, checked, recordedAt) {
  return {
    ...item,
    checked,
    checked_at: checked ? recordedAt : null,
    checked_state_recorded_at: recordedAt,
    hidden_until: null,
  };
}

async function createItemWithOfflineFallback(root, state, listId, payload) {
  if (isDemoList(root)) {
    return createDemoItem(state, payload);
  }

  const recordedAt = new Date().toISOString();
  const clientItemId = createOfflineId(OFFLINE_ITEM_ID_PREFIX);
  const mutation = {
    mutation_id: createOfflineId(OFFLINE_MUTATION_ID_PREFIX),
    type: "create",
    client_item_id: clientItemId,
    recorded_at: recordedAt,
    payload,
  };
  const applyLocalChange = () => {
    const localItem = createOfflineItem(state, listId, clientItemId, payload, recordedAt);
    upsertItem(state, localItem);
    return localItem;
  };

  if (shouldQueueItemMutation(state)) {
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }

  try {
    return await postJson(`/api/v1/lists/${listId}/items`, payload);
  } catch (error) {
    if (!isOfflineRequestError(error)) {
      throw error;
    }
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }
}

async function updateItemWithOfflineFallback(root, state, itemId, payload) {
  if (isDemoList(root)) {
    return updateDemoItem(state, itemId, payload);
  }

  const existingItem = state.items.get(itemId);
  const recordedAt = new Date().toISOString();
  const mutation = {
    mutation_id: createOfflineId(OFFLINE_MUTATION_ID_PREFIX),
    type: "update",
    item_id: itemId,
    recorded_at: recordedAt,
    payload,
  };
  const applyLocalChange = () => {
    const localItem = { ...existingItem, ...payload };
    upsertItem(state, localItem);
    return localItem;
  };

  if (shouldQueueItemMutation(state, itemId)) {
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }

  try {
    return await fetchJson(`/api/v1/items/${itemId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (error) {
    if (!isOfflineRequestError(error)) {
      throw error;
    }
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }
}

async function moveItemWithOfflineFallback(root, state, itemId, payload) {
  if (isDemoList(root)) {
    return updateDemoItem(state, itemId, payload);
  }

  if (shouldQueueItemMutation(state, itemId) || isBrowserOffline()) {
    throw new Error(
      translate(
        "list_detail.item_move_online_required",
        {},
        "Move items while online so both lists stay in sync.",
      ),
    );
  }

  return fetchJson(`/api/v1/items/${itemId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

async function setItemCheckedWithOfflineFallback(root, state, itemId, checked) {
  if (isDemoList(root)) {
    return setDemoItemChecked(state, itemId, checked);
  }

  const existingItem = state.items.get(itemId);
  const recordedAt = new Date().toISOString();
  const mutation = {
    mutation_id: createOfflineId(OFFLINE_MUTATION_ID_PREFIX),
    type: "set_checked",
    item_id: itemId,
    recorded_at: recordedAt,
    checked,
  };
  const applyLocalChange = () => {
    const localItem = applyLocalCheckedState(existingItem, checked, recordedAt);
    upsertItem(state, localItem);
    return localItem;
  };

  if (shouldQueueItemMutation(state, itemId)) {
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }

  try {
    return await postJson(`/api/v1/items/${itemId}/${checked ? "check" : "uncheck"}`, {});
  } catch (error) {
    if (!isOfflineRequestError(error)) {
      throw error;
    }
    return queueOfflineMutation(root, state, mutation, applyLocalChange);
  }
}

async function saveCategoryOrder(root, state) {
  if (isDemoList(root)) {
    const categoryIds = getManualCategoryIds(state);
    state.categoryOrder = new Map(categoryIds.map((categoryId, index) => [categoryId, index]));
    return;
  }

  const listId = root.dataset.listId;
  const categoryIds = getManualCategoryIds(state);
  const response = await fetchJson(`/api/v1/lists/${listId}/category-order`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ category_ids: categoryIds }),
  });
  state.categoryOrder = new Map(response.map((entry) => [entry.category_id, entry.sort_order]));
}

function syncItemMoveSelect(root, state, currentListId) {
  const field = root.querySelector("[data-item-edit-list-field]");
  const select = root.querySelector("[data-item-edit-list-select]");
  const lists = state.lists || [];
  if (!(field instanceof HTMLElement) || !(select instanceof HTMLSelectElement)) {
    return;
  }

  field.hidden = lists.length <= 1;
  select.innerHTML = "";
  lists.forEach((list) => {
    const option = document.createElement("option");
    option.value = list.id;
    option.textContent = list.name;
    select.appendChild(option);
  });
  select.value = currentListId || root.dataset.listId || "";
}

function showItemMovedMessage(root, targetListId) {
  setListMessage(
    root,
    "success",
    translate("list_detail.item_moved", {}, "Item moved to another list."),
    {
      href: `/lists/${encodeURIComponent(targetListId)}`,
      label: translate("list_detail.go_to_list", {}, "Go to list"),
    },
  );
}

function ensureCategoryOrderStatus(root) {
  let statusNode = root.querySelector("[data-category-order-status]");
  if (statusNode instanceof HTMLElement) {
    return statusNode;
  }

  const categoryList = root.querySelector("[data-list-settings-category-list]");
  if (!(categoryList instanceof HTMLElement)) {
    return null;
  }

  statusNode = document.createElement("p");
  statusNode.className = "settings-category-status";
  statusNode.dataset.categoryOrderStatus = "";
  statusNode.hidden = true;
  categoryList.before(statusNode);
  return statusNode;
}

function setCategoryOrderSaveStatus(root, state, status, message = "") {
  state.categoryOrderSaveStatus = status;
  state.categoryOrderSaveMessage = message;
  const statusNode = ensureCategoryOrderStatus(root);
  if (!(statusNode instanceof HTMLElement)) {
    return;
  }

  statusNode.hidden = !status;
  statusNode.textContent = message;
  statusNode.classList.toggle("is-saving", status === "saving");
  statusNode.classList.toggle("is-error", status === "error");
}

async function flushCategoryOrderSaveQueue(root, state) {
  const tracker = state.categoryOrderSaveQueue;
  if (!tracker || tracker.inFlight) {
    return tracker?.promise || null;
  }

  tracker.inFlight = true;
  try {
    while (tracker.queuedIds) {
      const categoryIds = [...tracker.queuedIds];
      tracker.queuedIds = null;
      const response = await fetchJson(`/api/v1/lists/${root.dataset.listId}/category-order`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ category_ids: categoryIds }),
      });
      if (!tracker.queuedIds && categoryIdsEqual(getManualCategoryIds(state), categoryIds)) {
        state.categoryOrder = new Map(
          response.map((entry) => [entry.category_id, entry.sort_order])
        );
        renderItems(root, state);
        renderCategoryOrderSettings(root, state);
        persistOfflineListState(root, state);
      }
    }
    setCategoryOrderSaveStatus(root, state, "", "");
  } catch (error) {
    tracker.queuedIds = null;
    setCategoryOrderSaveStatus(
      root,
      state,
      "error",
      translate("list_detail.category_order_save_failed", {}, "Could not save category order.")
    );
    setListMessage(
      root,
      "error",
      error instanceof Error
        ? error.message
        : translate("list_detail.category_order_save_failed", {}, "Could not save category order.")
    );
  } finally {
    tracker.inFlight = false;
    tracker.promise = null;
    if (tracker.queuedIds) {
      tracker.promise = flushCategoryOrderSaveQueue(root, state);
    }
  }

  return tracker.promise;
}

function saveCategoryOrderInBackground(root, state) {
  if (isDemoList(root)) {
    const categoryIds = getManualCategoryIds(state);
    state.categoryOrder = new Map(categoryIds.map((categoryId, index) => [categoryId, index]));
    setCategoryOrderSaveStatus(root, state, "", "");
    return Promise.resolve();
  }

  if (!state.categoryOrderSaveQueue) {
    state.categoryOrderSaveQueue = {
      inFlight: false,
      promise: null,
      queuedIds: null,
    };
  }

  state.categoryOrderSaveQueue.queuedIds = getManualCategoryIds(state);
  setCategoryOrderSaveStatus(
    root,
    state,
    "saving",
    translate("list_detail.category_order_saving", {}, "Saving category order...")
  );
  if (!state.categoryOrderSaveQueue.inFlight) {
    state.categoryOrderSaveQueue.promise = flushCategoryOrderSaveQueue(root, state);
  }
  return state.categoryOrderSaveQueue.promise || Promise.resolve();
}

async function saveDisabledCategories(root, state) {
  if (isDemoList(root)) {
    setDisabledCategoryIds(state, getDisabledCategoryIds(state));
    return;
  }

  const listId = root.dataset.listId;
  const response = await fetchJson(`/api/v1/lists/${listId}/disabled-categories`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ category_ids: getDisabledCategoryIds(state) }),
  });
  setDisabledCategoryIds(state, response.category_ids || []);
}

function itemCountForCategory(state, categoryId) {
  return [...state.items.values()].filter((item) => item.category_id === categoryId).length;
}

function unassignCategoryItems(state, categoryId) {
  const previousCategoryIds = [];
  state.items.forEach((item) => {
    if (item.category_id !== categoryId) {
      return;
    }
    previousCategoryIds.push([item.id, item.category_id]);
    item.category_id = null;
  });
  return previousCategoryIds;
}

function restoreItemCategoryIds(state, previousCategoryIds) {
  previousCategoryIds.forEach(([itemId, categoryId]) => {
    const item = state.items.get(itemId);
    if (item) {
      item.category_id = categoryId;
    }
  });
}

function categoryDisableConfirmText(category, affectedCount) {
  return translatePlural(
    "list_detail.disable_category_confirm",
    affectedCount,
    { name: category.name },
    {
      one: "Disable {name}? 1 item in this category will lose its category.",
      other: "Disable {name}? {count} items in this category will lose their category.",
    },
  );
}

async function moveEditingItemToList(root, state, targetListId) {
  const itemId = state.editingItemId;
  const existingItem = itemId ? state.items.get(itemId) : null;
  const existingListId = existingItem?.list_id || root.dataset.listId || "";
  if (!itemId || !existingItem || !targetListId || targetListId === existingListId) {
    return true;
  }

  cancelItemEditSaveTimer(state);
  if (state.itemEditSaveInFlight) {
    await state.itemEditSaveInFlight;
  }

  const payload = readItemEditFormPayload(root);
  if (!payload?.name) {
    setItemEditStatus(root, "error", translate("list_detail.item_name_required", {}, "Please enter an item name."));
    setListMessage(root, "error", translate("list_detail.item_name_required", {}, "Please enter an item name."));
    return false;
  }

  setItemEditStatus(root, "saving", translate("list_detail.item_saving", {}, "Saving..."));
  try {
    const movedItem = await moveItemWithOfflineFallback(root, state, itemId, {
      ...payload,
      list_id: targetListId,
    });
    removeItem(state, movedItem.id);
    persistOfflineListState(root, state);
    setItemEditPanelOpen(root, state, null);
    showMovedItemNotice(
      root,
      state,
      createMovedItemNotice(root, state, existingItem, movedItem, targetListId)
    );
    setListMessage(root, "", "");
    return true;
  } catch (error) {
    syncItemMoveSelect(root, state, existingListId);
    const message = error instanceof Error ? error.message : translate("list_detail.item_update_failed", {}, "Could not save item.");
    setItemEditStatus(root, "error", message);
    setListMessage(root, "error", message);
    updateItemEditUndoButton(root, state);
    return false;
  }
}

function ensureCategoryDisableConfirm(root) {
  let overlay = root.querySelector("[data-category-disable-confirm-overlay]");
  if (overlay instanceof HTMLElement) {
    return {
      overlay,
      panel: root.querySelector("[data-category-disable-confirm-panel]"),
      title: root.querySelector("[data-category-disable-confirm-title]"),
      copy: root.querySelector("[data-category-disable-confirm-copy]"),
      confirmButton: root.querySelector("[data-category-disable-confirm-confirm]"),
    };
  }

  overlay = document.createElement("div");
  overlay.className = "item-modal category-disable-confirm-modal";
  overlay.dataset.categoryDisableConfirmOverlay = "";
  overlay.hidden = true;

  const backdrop = document.createElement("button");
  backdrop.type = "button";
  backdrop.className = "item-modal-backdrop";
  backdrop.dataset.categoryDisableConfirmCancel = "";
  backdrop.setAttribute("aria-label", translate("common.cancel", {}, "Cancel"));
  overlay.appendChild(backdrop);

  const panel = document.createElement("section");
  panel.className = "dashboard-card item-edit-panel category-disable-confirm-panel";
  panel.dataset.categoryDisableConfirmPanel = "";
  panel.hidden = true;

  const header = document.createElement("div");
  header.className = "add-item-panel-header";

  const headingWrap = document.createElement("div");
  const label = document.createElement("p");
  label.className = "dashboard-label";
  label.textContent = translate("list_detail.list_settings", {}, "List settings");
  const title = document.createElement("h2");
  title.dataset.categoryDisableConfirmTitle = "";
  headingWrap.append(label, title);

  const closeButton = document.createElement("button");
  closeButton.type = "button";
  closeButton.className = "add-item-close";
  closeButton.dataset.categoryDisableConfirmCancel = "";
  closeButton.setAttribute("aria-label", translate("common.cancel", {}, "Cancel"));
  closeButton.textContent = "\u00d7";

  header.append(headingWrap, closeButton);
  panel.appendChild(header);

  const copy = document.createElement("p");
  copy.className = "dashboard-helper";
  copy.dataset.categoryDisableConfirmCopy = "";
  panel.appendChild(copy);

  const actions = document.createElement("div");
  actions.className = "item-edit-actions";

  const cancelButton = document.createElement("button");
  cancelButton.type = "button";
  cancelButton.dataset.categoryDisableConfirmCancel = "";
  cancelButton.textContent = translate("common.cancel", {}, "Cancel");
  actions.appendChild(cancelButton);

  const confirmButton = document.createElement("button");
  confirmButton.type = "button";
  confirmButton.className = "danger-button";
  confirmButton.dataset.categoryDisableConfirmConfirm = "";
  confirmButton.textContent = translate(
    "list_detail.disable_category_confirm_action",
    {},
    "Disable category"
  );
  actions.appendChild(confirmButton);

  panel.appendChild(actions);
  overlay.appendChild(panel);
  root.appendChild(overlay);

  return { overlay, panel, title, copy, confirmButton };
}

function setCategoryDisableConfirmOpen(root, isOpen) {
  const overlay = root.querySelector("[data-category-disable-confirm-overlay]");
  const panel = root.querySelector("[data-category-disable-confirm-panel]");
  if (!(overlay instanceof HTMLElement) || !(panel instanceof HTMLElement)) {
    return;
  }

  overlay.hidden = !isOpen;
  panel.hidden = !isOpen;
  syncModalState(root);
}

function confirmCategoryDisable(root, category, affectedCount) {
  const { overlay, title, copy, confirmButton } = ensureCategoryDisableConfirm(root);
  if (
    !(overlay instanceof HTMLElement) ||
    !(title instanceof HTMLElement) ||
    !(copy instanceof HTMLElement) ||
    !(confirmButton instanceof HTMLButtonElement)
  ) {
    return Promise.resolve(false);
  }

  title.textContent = translate(
    "list_detail.disable_category_confirm_title",
    { name: category.name },
    "Disable {name}?"
  );
  copy.textContent = categoryDisableConfirmText(category, affectedCount);
  setCategoryDisableConfirmOpen(root, true);

  return new Promise((resolve) => {
    let settled = false;
    const settle = (value) => {
      if (settled) {
        return;
      }
      settled = true;
      overlay.removeEventListener("click", handleClick);
      document.removeEventListener("keydown", handleKeydown);
      setCategoryDisableConfirmOpen(root, false);
      resolve(value);
    };
    const handleClick = (event) => {
      const eventTarget = event.target;
      if (!(eventTarget instanceof Element)) {
        return;
      }
      if (eventTarget.closest("[data-category-disable-confirm-confirm]")) {
        settle(true);
        return;
      }
      if (eventTarget.closest("[data-category-disable-confirm-cancel]")) {
        settle(false);
      }
    };
    const handleKeydown = (event) => {
      if (event.key === "Escape") {
        settle(false);
      }
    };

    overlay.addEventListener("click", handleClick);
    document.addEventListener("keydown", handleKeydown);
    window.setTimeout(() => {
      confirmButton.focus();
    }, 0);
  });
}

async function setCategoryDisabled(root, state, categoryId, disabled) {
  const category = state.categories.get(categoryId);
  if (!category || isCategoryDisabled(state, categoryId) === disabled) {
    return false;
  }

  const affectedCount = itemCountForCategory(state, categoryId);
  if (disabled && affectedCount > 0) {
    const confirmed = await confirmCategoryDisable(root, category, affectedCount);
    if (!confirmed) {
      return false;
    }
  }

  const previousDisabledCategoryIds = new Set(state.disabledCategoryIds || []);
  const previousItemCategories = disabled ? unassignCategoryItems(state, categoryId) : [];
  if (!state.disabledCategoryIds) {
    state.disabledCategoryIds = new Set();
  }
  if (disabled) {
    state.disabledCategoryIds.add(categoryId);
  } else {
    state.disabledCategoryIds.delete(categoryId);
  }

  try {
    await saveDisabledCategories(root, state);
  } catch (error) {
    setDisabledCategoryIds(state, [...previousDisabledCategoryIds]);
    restoreItemCategoryIds(state, previousItemCategories);
    throw error;
  }

  syncCategoryRadioGroups(root, state);
  renderItems(root, state);
  renderCategoryOrderSettings(root, state);
  persistOfflineListState(root, state);
  return true;
}

function createCategoryGrabberIcon() {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("focusable", "false");

  [
    [9, 5],
    [9, 12],
    [9, 19],
    [15, 5],
    [15, 12],
    [15, 19],
  ].forEach(([cx, cy]) => {
    const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("cx", String(cx));
    circle.setAttribute("cy", String(cy));
    circle.setAttribute("r", "1.6");
    circle.setAttribute("fill", "currentColor");
    svg.appendChild(circle);
  });

  return svg;
}

function createCategoryVisibilityIcon(disabled) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("focusable", "false");

  const paths = disabled
    ? [
        "M3 3l18 18",
        "M10.6 10.6a2 2 0 0 0 2.8 2.8",
        "M9.5 5.6A10.8 10.8 0 0 1 12 5c5 0 9 5 9 7a9.8 9.8 0 0 1-2.4 3.6",
        "M6.4 6.4C4.3 7.8 3 10.2 3 12c0 2 4 7 9 7a10.3 10.3 0 0 0 4.1-.9",
      ]
    : [
        "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z",
        "M12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6z",
      ];

  paths.forEach((pathValue) => {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", pathValue);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", "currentColor");
    path.setAttribute("stroke-width", "2");
    path.setAttribute("stroke-linecap", "round");
    path.setAttribute("stroke-linejoin", "round");
    svg.appendChild(path);
  });
  return svg;
}

function clearCategoryDragState(root) {
  root.querySelectorAll(".settings-category-row").forEach((row) => {
    row.classList.remove("is-dragging", "is-drag-over", "is-drop-before", "is-drop-after");
  });
}

function clearCategoryDropIndicators(root) {
  root.querySelectorAll(".settings-category-row").forEach((row) => {
    row.classList.remove("is-drag-over", "is-drop-before", "is-drop-after");
  });
}

function categoryDropPosition(row, clientY) {
  const rect = row.getBoundingClientRect();
  return clientY > rect.top + rect.height / 2 ? "after" : "before";
}

function setCategoryDropIndicator(root, state, row, position) {
  if (!(row instanceof HTMLElement) || !row.dataset.categoryId) {
    state.categoryDropTarget = null;
    clearCategoryDropIndicators(root);
    return;
  }

  clearCategoryDropIndicators(root);
  row.classList.add(position === "after" ? "is-drop-after" : "is-drop-before");
  state.categoryDropTarget = {
    categoryId: row.dataset.categoryId,
    position: position === "after" ? "after" : "before",
  };
}

function categoryInsertionIndex(orderedCategoryIds, draggedCategoryId, targetCategoryId, position) {
  const currentIndex = orderedCategoryIds.indexOf(draggedCategoryId);
  const targetIndex = orderedCategoryIds.indexOf(targetCategoryId);
  if (currentIndex === -1 || targetIndex === -1 || draggedCategoryId === targetCategoryId) {
    return -1;
  }

  let nextIndex = targetIndex + (position === "after" ? 1 : 0);
  if (currentIndex < nextIndex) {
    nextIndex -= 1;
  }
  return Math.max(0, Math.min(nextIndex, orderedCategoryIds.length - 1));
}

function applyCategoryReorder(root, state, draggedCategoryId, targetCategoryId, position) {
  const orderedCategoryIds = getOrderedCategoryIds(state);
  const nextIndex = categoryInsertionIndex(
    orderedCategoryIds,
    draggedCategoryId,
    targetCategoryId,
    position
  );
  if (nextIndex < 0) {
    return false;
  }

  const nextOrderedCategoryIds = reorderCategoryIds(
    orderedCategoryIds,
    draggedCategoryId,
    nextIndex
  );
  if (categoryIdsEqual(nextOrderedCategoryIds, orderedCategoryIds)) {
    return false;
  }

  setCategoryOrder(state, deriveManualCategoryIds(state, nextOrderedCategoryIds));
  renderItems(root, state);
  renderCategoryOrderSettings(root, state);
  persistOfflineListState(root, state);
  saveCategoryOrderInBackground(root, state);
  return true;
}

function setItemEditPanelOpen(root, state, itemId) {
  const panel = root.querySelector("[data-item-edit-panel]");
  const overlay = root.querySelector("[data-item-edit-overlay]");
  const form = root.querySelector("[data-item-edit-form]");
  const title = root.querySelector("[data-item-edit-title]");
  if (
    !(panel instanceof HTMLElement) ||
    !(overlay instanceof HTMLElement) ||
    !(form instanceof HTMLFormElement) ||
    !title
  ) {
    return;
  }

  const previousEditingItemId = state.editingItemId;
  state.editingItemId = itemId;
  if (!itemId) {
    cancelItemEditSaveTimer(state);
    state.itemEditLastSavedPayload = null;
    state.itemEditNeedsSave = false;
    overlay.hidden = true;
    panel.hidden = true;
    form.reset();
    const editSearch = root.querySelector("[data-item-edit-category-search]");
    if (editSearch instanceof HTMLInputElement) {
      editSearch.value = "";
    }
    setItemEditStatus(root, "", "");
    updateItemEditUndoButton(root, state);
    syncModalState(root);
    return;
  }

  const item = state.items.get(itemId);
  if (!item) {
    overlay.hidden = true;
    panel.hidden = true;
    syncModalState(root);
    return;
  }

  setItemPanelOpen(root, false);
  overlay.hidden = false;
  panel.hidden = false;
  syncModalState(root);
  title.textContent = item.name;

  syncItemMoveSelect(root, state, item.list_id || root.dataset.listId);
  const editSearch = root.querySelector("[data-item-edit-category-search]");
  if (editSearch instanceof HTMLInputElement) {
    editSearch.value = "";
  }
  setItemEditFormValues(root, state, item);
  state.itemEditLastSavedPayload = itemEditPayloadFromItem(item);
  if (previousEditingItemId !== itemId) {
    setItemEditStatus(root, "", "");
  }

  updateItemEditUndoButton(root, state);
}

function renderCategoryOrderSettings(root, state) {
  const container = root.querySelector("[data-list-settings-category-list]");
  if (!(container instanceof HTMLElement)) {
    return;
  }

  container.innerHTML = "";
  const orderedCategories = getOrderedCategoryIds(state).map((categoryId) => state.categories.get(categoryId)).filter(Boolean);

  if (orderedCategories.length === 0) {
    const emptyState = document.createElement("p");
    emptyState.className = "dashboard-helper";
    emptyState.textContent = translate(
      "list_detail.create_categories_admin",
      {},
      "Create categories in admin to customize the order for this list."
    );
    container.appendChild(emptyState);
    return;
  }

  orderedCategories.forEach((category, index) => {
    const disabled = isCategoryDisabled(state, category.id);
    const row = document.createElement("div");
    row.className = `settings-category-row${disabled ? " is-disabled" : ""}`;
    row.dataset.categoryId = category.id;
    row.draggable = false;

    const grabber = document.createElement("button");
    grabber.type = "button";
    grabber.className = "settings-category-grabber";
    grabber.dataset.settingsCategoryGrabber = category.id;
    grabber.draggable = false;
    grabber.setAttribute(
      "aria-label",
      translate("list_detail.drag_category", { name: category.name }, "Drag {name} to reorder")
    );
    grabber.appendChild(createCategoryGrabberIcon());
    row.appendChild(grabber);

    const swatch = document.createElement("span");
    swatch.className = "item-category-swatch";
    swatch.style.background = category.color || CATEGORY_SWATCH_FALLBACK_COLOR;
    row.appendChild(swatch);

    const copy = document.createElement("div");
    copy.className = "settings-category-copy";

    const title = document.createElement("strong");
    title.textContent = category.name;
    copy.appendChild(title);

    const meta = document.createElement("span");
    meta.textContent = disabled
      ? translate("list_detail.disabled_for_list", {}, "Disabled for this list")
      : state.categoryOrder.has(category.id)
        ? translate("list_detail.pinned_in_order", {}, "Pinned in this list order")
        : translate("list_detail.alphabetical_until_moved", {}, "Alphabetical until you move it");
    copy.appendChild(meta);
    row.appendChild(copy);

    const actions = document.createElement("div");
    actions.className = "settings-category-actions";

    const moveGroup = document.createElement("div");
    moveGroup.className = "settings-category-move-group";

    const moveUp = document.createElement("button");
    moveUp.type = "button";
    moveUp.dataset.settingsCategoryMove = "up";
    moveUp.dataset.categoryId = category.id;
    moveUp.setAttribute(
      "aria-label",
      translate("list_detail.move_category_up", { name: category.name }, "Move {name} up")
    );
    moveUp.disabled = index === 0;
    moveUp.textContent = "↑";
    moveGroup.appendChild(moveUp);

    const moveDown = document.createElement("button");
    moveDown.type = "button";
    moveDown.dataset.settingsCategoryMove = "down";
    moveDown.dataset.categoryId = category.id;
    moveDown.setAttribute(
      "aria-label",
      translate("list_detail.move_category_down", { name: category.name }, "Move {name} down")
    );
    moveDown.disabled = index === orderedCategories.length - 1;
    moveDown.textContent = "↓";
    moveGroup.appendChild(moveDown);
    actions.appendChild(moveGroup);

    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "settings-category-toggle";
    toggle.dataset.settingsCategoryToggle = category.id;
    toggle.setAttribute(
      "aria-label",
      disabled
        ? translate("list_detail.enable_category", { name: category.name }, "Enable {name}")
        : translate("list_detail.disable_category", { name: category.name }, "Disable {name}")
    );
    toggle.title = toggle.getAttribute("aria-label") || "";
    toggle.appendChild(createCategoryVisibilityIcon(disabled));
    actions.appendChild(toggle);

    row.appendChild(actions);
    container.appendChild(row);
  });
}

function setListSettingsOpen(root, state, isOpen) {
  const overlay = root.querySelector("[data-list-settings-overlay]");
  const panel = root.querySelector("[data-list-settings-panel]");
  if (!(overlay instanceof HTMLElement) || !(panel instanceof HTMLElement)) {
    return;
  }

  overlay.hidden = !isOpen;
  panel.hidden = !isOpen;

  if (isOpen) {
    setItemPanelOpen(root, false);
    setItemEditPanelOpen(root, state, null);
    setListName(root, state, state.listName || listTitleText(root));
    renderCategoryOrderSettings(root, state);
  }

  syncModalState(root);
}

function renderItemSuggestions(root, state) {
  const suggestionsNode = root.querySelector("[data-item-suggestions]");
  const suggestionsSlot = root.querySelector("[data-item-suggestions-slot]");
  const nameInput = root.querySelector("[data-item-name-input]");

  if (
    !(suggestionsNode instanceof HTMLElement) ||
    !(suggestionsSlot instanceof HTMLElement) ||
    !(nameInput instanceof HTMLInputElement)
  ) {
    return;
  }

  const query = normalizeSearchText(nameInput.value);
  if (!query) {
    suggestionsNode.innerHTML = "";
    suggestionsSlot.classList.remove("is-active");
    return;
  }

  const matches = [...state.items.values()]
    .filter((item) => !isItemHidden(item))
    .map((item) => ({ item, match: itemSuggestionMatch(item.name, query) }))
    .filter(({ match }) => match !== null)
    .sort((left, right) => {
      if (left.match.rank !== right.match.rank) {
        return left.match.rank - right.match.rank;
      }
      if (left.match.distance !== right.match.distance) {
        return left.match.distance - right.match.distance;
      }
      if (left.item.checked !== right.item.checked) {
        return Number(left.item.checked) - Number(right.item.checked);
      }
      return left.item.name.localeCompare(right.item.name);
    })
    .map(({ item }) => item)
    .slice(0, 4);

  if (matches.length === 0) {
    suggestionsNode.innerHTML = "";
    suggestionsSlot.classList.remove("is-active");
    return;
  }

  const previousMatchIds = [...suggestionsNode.querySelectorAll("[data-item-reuse]")]
    .map((button) => button.dataset.itemReuse || "")
    .join("\u001f");
  const nextMatchIds = matches.map((item) => item.id).join("\u001f");
  if (previousMatchIds === nextMatchIds) {
    suggestionsSlot.classList.add("is-active");
    return;
  }

  const reusableSuggestions = new Map();
  suggestionsNode.querySelectorAll(".item-suggestion").forEach((suggestion) => {
    const itemId = suggestion.querySelector("[data-item-reuse]").dataset.itemReuse;
    reusableSuggestions.set(itemId, suggestion);
  });
  const staleSuggestions = new Set(reusableSuggestions.values());

  matches.forEach((item, index) => {
    let wrapper = reusableSuggestions.get(item.id);
    if (wrapper instanceof HTMLElement) {
      staleSuggestions.delete(wrapper);
    } else {
      wrapper = document.createElement("article");
      wrapper.className = `item-card item-suggestion${item.checked ? " is-checked" : ""}`;
      wrapper.style.setProperty("--suggestion-delay", `${index * 24}ms`);
      const categoryColor = item.category_id ? state.categories.get(item.category_id)?.color || "" : "";
      if (categoryColor) {
        wrapper.classList.add("has-category");
        wrapper.style.setProperty("--suggestion-category-color", categoryColor);
      }

      const main = document.createElement("div");
      main.className = "item-main";

      const button = document.createElement("button");
      button.type = "button";
      button.dataset.itemReuse = item.id;
      button.setAttribute(
        "aria-label",
        item.checked
          ? translate("list_detail.suggestion_add_back", { name: item.name }, "Add {name} back to the list")
          : translate("list_detail.suggestion_jump_to", { name: item.name }, "Jump to {name} in the list")
      );
      button.textContent = "+";
      main.appendChild(button);

      const copy = document.createElement("div");
      copy.className = "item-copy item-suggestion-copy";

      const title = document.createElement("strong");
      title.className = "item-name";
      title.textContent = item.name;
      copy.appendChild(title);

      const meta = document.createElement("span");
      meta.textContent = formatSuggestionMeta(state, item);
      copy.appendChild(meta);

      main.appendChild(copy);
      wrapper.appendChild(main);
    }

    const referenceNode = suggestionsNode.children[index] || null;
    if (referenceNode !== wrapper) {
      suggestionsNode.insertBefore(wrapper, referenceNode);
    }
  });
  staleSuggestions.forEach((suggestion) => suggestion.remove());

  suggestionsSlot.classList.add("is-active");
}

function highlightItem(root, state, itemId) {
  state.highlightedItemId = itemId;

  const itemCard = root.querySelector(`[data-item-card="${itemId}"]`);
  if (!(itemCard instanceof HTMLElement)) {
    return;
  }

  const existingTimer = state.highlightTimers.get(itemId);
  if (existingTimer) {
    window.clearTimeout(existingTimer);
  }

  itemCard.classList.add("is-highlighted");
  window.requestAnimationFrame(() => {
    window.requestAnimationFrame(() => {
      root.querySelector(`[data-item-card="${itemId}"]`)?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
  });
  const timeoutId = window.setTimeout(() => {
    if (state.highlightedItemId === itemId) {
      state.highlightedItemId = null;
    }
    root.querySelector(`[data-item-card="${itemId}"]`)?.classList.remove("is-highlighted");
    state.highlightTimers.delete(itemId);
  }, 1800);
  state.highlightTimers.set(itemId, timeoutId);
}

function compareActiveItems(state, left, right) {
  const leftIsUncategorized = !left.category_id;
  const rightIsUncategorized = !right.category_id;
  if (leftIsUncategorized !== rightIsUncategorized) {
    return Number(rightIsUncategorized) - Number(leftIsUncategorized);
  }

  if (!leftIsUncategorized && !rightIsUncategorized) {
    const leftCategory = categorySortKey(state, left.category_id);
    const rightCategory = categorySortKey(state, right.category_id);
    if (leftCategory.isExplicit !== rightCategory.isExplicit) {
      return Number(rightCategory.isExplicit) - Number(leftCategory.isExplicit);
    }
    if (leftCategory.sortOrder !== rightCategory.sortOrder) {
      return leftCategory.sortOrder - rightCategory.sortOrder;
    }
    if (leftCategory.name !== rightCategory.name) {
      return leftCategory.name.localeCompare(rightCategory.name);
    }
  }

  if (left.sort_order !== right.sort_order) {
    return left.sort_order - right.sort_order;
  }
  return left.name.localeCompare(right.name);
}

const CHECKED_ITEMS_INITIAL_LIMIT = 10;
const CHECKED_ITEMS_LOAD_MORE_COUNT = 100;

function compareCheckedItems(left, right) {
  const leftCheckedAt = left.checked_at ? Date.parse(left.checked_at) : 0;
  const rightCheckedAt = right.checked_at ? Date.parse(right.checked_at) : 0;
  if (leftCheckedAt !== rightCheckedAt) {
    return rightCheckedAt - leftCheckedAt;
  }
  return left.name.localeCompare(right.name);
}

function getActiveGroupOrder(state, items) {
  const groupKeys = new Set(
    items.map((item) => item.category_id || "uncategorized")
  );

  const orderedKeys = ["uncategorized"];
  getOrderedCategoryIds(state).forEach((categoryId) => {
    if (groupKeys.has(categoryId)) {
      orderedKeys.push(categoryId);
    }
  });

  return orderedKeys.filter((groupKey) => groupKeys.has(groupKey));
}

function createMovedItemNoticeElement(root, state, notice) {
  const article = document.createElement("article");
  article.className = `item-card item-move-notice${notice.isExpiring ? " is-expiring" : ""}`;
  article.dataset.movedItemNotice = notice.id;

  const copy = document.createElement("div");
  copy.className = "item-move-notice-copy";

  const message = document.createElement("p");
  message.textContent = translate(
    "list_detail.item_moved_named",
    { name: notice.itemName, list: notice.targetListName },
    "{name} moved to {list}."
  );
  copy.appendChild(message);
  article.appendChild(copy);

  const actions = document.createElement("div");
  actions.className = "item-move-notice-actions";

  const undoButton = document.createElement("button");
  undoButton.type = "button";
  undoButton.dataset.movedItemUndo = notice.id;
  undoButton.textContent = translate("common.undo", {}, "Undo");
  actions.appendChild(undoButton);

  const targetLink = document.createElement("a");
  targetLink.href = `/lists/${encodeURIComponent(notice.targetListId)}`;
  targetLink.textContent = translate("list_detail.go_to_list", {}, "Go to list");
  actions.appendChild(targetLink);

  article.appendChild(actions);

  const timer = document.createElement("div");
  timer.className = "item-move-notice-timer";
  article.appendChild(timer);

  return article;
}

function renderItems(root, state) {
  const container = root.querySelector("[data-item-list]");
  const emptyState = root.querySelector("[data-item-empty]");
  if (!container || !emptyState) {
    return;
  }

  const renderNow = Date.now();
  const decoratedItems = [...state.items.values()].map((item) => decorateItem(state, item));
  const movedNoticeItems = [...(state.movedItemNotices?.values() || [])].map(movedItemNoticeRenderItem);
  const renderableItems = decoratedItems.concat(movedNoticeItems);
  const activeItems = renderableItems
    .filter((item) => !item.checked && !isItemHidden(item, renderNow))
    .sort((left, right) => compareActiveItems(state, left, right));
  const hiddenItems = renderableItems
    .filter((item) => !item.checked && isItemHidden(item, renderNow))
    .sort((left, right) => compareActiveItems(state, left, right));
  const checkedItems = renderableItems
    .filter((item) => item.checked)
    .sort(compareCheckedItems);

  container.innerHTML = "";
  const hasItems = activeItems.length > 0 || hiddenItems.length > 0 || checkedItems.length > 0;
  emptyState.hidden = hasItems;
  emptyState.style.display = hasItems ? "none" : "";
  if (!hasItems) {
    return;
  }

  const groupedActiveItems = new Map();
  activeItems.forEach((item) => {
    const groupKey = item.category_id || "uncategorized";
    if (!groupedActiveItems.has(groupKey)) {
      groupedActiveItems.set(groupKey, []);
    }
    groupedActiveItems.get(groupKey).push(item);
  });

  getActiveGroupOrder(state, activeItems).forEach((groupKey) => {
    const items = groupedActiveItems.get(groupKey) || [];
    const section = document.createElement("section");
    section.className = "item-category-group";

    const category = groupKey === "uncategorized" ? null : state.categories.get(groupKey);
    const heading = document.createElement("div");
    heading.className = "item-category-header";

    const swatch = document.createElement("span");
    swatch.className = "item-category-swatch";
    swatch.style.background = category?.color || CATEGORY_SWATCH_FALLBACK_COLOR;
    heading.appendChild(swatch);

    const headingCopy = document.createElement("div");
    headingCopy.className = "item-category-copy";
    const headingTitle = document.createElement("h3");
    headingTitle.textContent = category?.name || translate("list_detail.uncategorized", {}, "Uncategorized");
    headingCopy.appendChild(headingTitle);

    const headingMeta = document.createElement("p");
    headingMeta.className = "item-category-meta";
    headingMeta.textContent = translatePlural("list_detail.item_count", items.length, {}, { one: "{count} item", other: "{count} items" });
    heading.appendChild(headingCopy);

    const headingActions = document.createElement("div");
    headingActions.className = "item-category-actions";

    const quickAddButton = document.createElement("button");
    quickAddButton.className = "item-category-quick-add";
    quickAddButton.type = "button";
    quickAddButton.dataset.itemQuickAddCategory = category?.id || "";
    const quickAddLabel = category
      ? translate("list_detail.quick_add_category", { name: category.name }, "Quick add to {name}")
      : translate("list_detail.quick_add_uncategorized", {}, "Quick add uncategorized item");
    quickAddButton.setAttribute("aria-label", quickAddLabel);
    quickAddButton.title = quickAddLabel;
    const quickAddIcon = document.createElement("span");
    quickAddIcon.setAttribute("aria-hidden", "true");
    quickAddIcon.textContent = "+";
    quickAddButton.appendChild(quickAddIcon);
    headingActions.appendChild(quickAddButton);
    headingActions.appendChild(headingMeta);
    heading.appendChild(headingActions);

    section.appendChild(heading);

    items.forEach((item) => {
      if (item.movedNotice) {
        section.appendChild(createMovedItemNoticeElement(root, state, item.movedNotice));
        return;
      }

      const article = document.createElement("article");
      article.className = `item-card${item.checked ? " is-checked" : ""}${
        state.highlightedItemId === item.id ? " is-highlighted" : ""
      }`;
      article.dataset.itemCard = item.id;
      article.dataset.itemEdit = item.id;

      const swipeAction = document.createElement("div");
      swipeAction.className = "item-swipe-action";
      swipeAction.setAttribute("aria-hidden", "true");
      swipeAction.textContent = translate("list_detail.hide_for_later_short", {}, "Later 4h");
      article.appendChild(swipeAction);

      const cardContent = document.createElement("div");
      cardContent.className = "item-card-content";

      const main = document.createElement("div");
      main.className = "item-main";

      const checkButton = document.createElement("button");
      checkButton.className = `item-check${item.checked ? " is-checked" : ""}`;
      checkButton.type = "button";
      checkButton.dataset.itemToggle = item.id;
      checkButton.setAttribute(
        "aria-label",
        item.checked
          ? translate("list_detail.uncheck_item", { name: item.name }, "Uncheck {name}")
          : translate("list_detail.check_item", { name: item.name }, "Check {name}")
      );
      main.appendChild(checkButton);

      const copy = document.createElement("div");
      copy.className = "item-copy";

      const title = document.createElement("h3");
      title.className = "item-name";
      title.textContent = item.name;
      copy.appendChild(title);

      if (item.quantity_text) {
        const quantity = document.createElement("p");
        quantity.className = "item-meta";
        quantity.textContent = translate("list_detail.quantity_prefix", { quantity: item.quantity_text }, "Qty: {quantity}");
        copy.appendChild(quantity);
      }

      if (item.note) {
        const note = document.createElement("p");
        note.className = "item-meta";
        note.textContent = item.note;
        copy.appendChild(note);
      }

      main.appendChild(copy);
      cardContent.appendChild(main);

      const actions = document.createElement("div");
      actions.className = "item-actions";

      const menuButton = document.createElement("button");
      menuButton.type = "button";
      menuButton.className = "item-more-button";
      menuButton.dataset.itemMenuToggle = item.id;
      menuButton.setAttribute(
        "aria-label",
        translate("list_detail.more_item_actions", { name: item.name }, "More actions for {name}")
      );
      menuButton.setAttribute("aria-expanded", String(state.openItemMenuId === item.id));
      menuButton.textContent = "⋯";
      actions.appendChild(menuButton);
      cardContent.appendChild(actions);

      article.appendChild(cardContent);

      const menu = document.createElement("div");
      menu.className = "item-more-menu";
      menu.hidden = state.openItemMenuId !== item.id;

      const hideButton = document.createElement("button");
      hideButton.type = "button";
      hideButton.dataset.itemHide = item.id;
      hideButton.textContent = translate("list_detail.hide_item_for_later_menu", {}, "Hide item for 4h");
      menu.appendChild(hideButton);
      article.appendChild(menu);
      section.appendChild(article);
    });

    container.appendChild(section);
  });

  if (hiddenItems.length > 0) {
    const section = document.createElement("section");
    section.className = "item-category-group item-hidden-group";

    const heading = document.createElement("div");
    heading.className = "item-category-header";

    const swatch = document.createElement("span");
    swatch.className = "item-category-swatch";
    swatch.style.background = CATEGORY_SWATCH_FALLBACK_COLOR;
    heading.appendChild(swatch);

    const headingCopy = document.createElement("div");
    headingCopy.className = "item-category-copy";
    const headingTitle = document.createElement("h3");
    headingTitle.textContent = translate("list_detail.hidden_for_later", {}, "Hidden for 4h");
    headingCopy.appendChild(headingTitle);

    const headingMeta = document.createElement("p");
    headingMeta.className = "item-category-meta";
    headingMeta.textContent = translatePlural("list_detail.item_count", hiddenItems.length, {}, { one: "{count} item", other: "{count} items" });
    headingCopy.appendChild(headingMeta);
    heading.appendChild(headingCopy);
    section.appendChild(heading);

    hiddenItems.forEach((item) => {
      if (item.movedNotice) {
        section.appendChild(createMovedItemNoticeElement(root, state, item.movedNotice));
        return;
      }

      const article = document.createElement("article");
      article.className = `item-card is-hidden${
        state.highlightedItemId === item.id ? " is-highlighted" : ""
      }`;
      article.dataset.itemCard = item.id;
      article.dataset.itemEdit = item.id;

      const cardContent = document.createElement("div");
      cardContent.className = "item-card-content";

      const main = document.createElement("div");
      main.className = "item-main";

      const unhideButton = document.createElement("button");
      unhideButton.className = "item-check item-hidden-clock";
      unhideButton.type = "button";
      unhideButton.dataset.itemUnhide = item.id;
      unhideButton.setAttribute(
        "aria-label",
        translate("list_detail.show_hidden_item", { name: item.name }, "Show {name} now")
      );
      unhideButton.textContent = formatHiddenUntilLabel(item, renderNow);
      main.appendChild(unhideButton);

      const copy = document.createElement("div");
      copy.className = "item-copy";

      const title = document.createElement("h3");
      title.className = "item-name";
      title.textContent = item.name;
      copy.appendChild(title);

      if (item.quantity_text) {
        const quantity = document.createElement("p");
        quantity.className = "item-meta";
        quantity.textContent = translate("list_detail.quantity_prefix", { quantity: item.quantity_text }, "Qty: {quantity}");
        copy.appendChild(quantity);
      }

      if (item.note) {
        const note = document.createElement("p");
        note.className = "item-meta";
        note.textContent = item.note;
        copy.appendChild(note);
      }

      main.appendChild(copy);
      cardContent.appendChild(main);
      article.appendChild(cardContent);
      section.appendChild(article);
    });

    container.appendChild(section);
  }

  if (checkedItems.length > 0) {
    const checkedTotalCount = checkedItems.length + (state.checkedRemainingCount || 0);
    const section = document.createElement("section");
    section.className = "item-category-group";

    const heading = document.createElement("div");
    heading.className = "item-category-header";

    const swatch = document.createElement("span");
    swatch.className = "item-category-swatch";
    swatch.style.background = CHECKED_CATEGORY_SWATCH_COLOR;
    heading.appendChild(swatch);

    const headingCopy = document.createElement("div");
    headingCopy.className = "item-category-copy";
    const headingTitle = document.createElement("h3");
    headingTitle.textContent = translate("list_detail.checked_off", {}, "Checked off");
    headingCopy.appendChild(headingTitle);

    const headingMeta = document.createElement("p");
    headingMeta.className = "item-category-meta";
    headingMeta.textContent = translatePlural("list_detail.item_count", checkedTotalCount, {}, { one: "{count} item", other: "{count} items" });
    heading.appendChild(headingCopy);
    const headingActions = document.createElement("div");
    headingActions.className = "item-category-actions";
    headingActions.appendChild(headingMeta);
    heading.appendChild(headingActions);
    section.appendChild(heading);

    checkedItems.forEach((item) => {
      if (item.movedNotice) {
        section.appendChild(createMovedItemNoticeElement(root, state, item.movedNotice));
        return;
      }

      const article = document.createElement("article");
      article.className = `item-card is-checked${
        state.highlightedItemId === item.id ? " is-highlighted" : ""
      }`;
      article.dataset.itemCard = item.id;
      article.dataset.itemEdit = item.id;

      const cardContent = document.createElement("div");
      cardContent.className = "item-card-content";

      const main = document.createElement("div");
      main.className = "item-main";

      const checkButton = document.createElement("button");
      checkButton.className = "item-check is-checked";
      checkButton.type = "button";
      checkButton.dataset.itemToggle = item.id;
      checkButton.setAttribute(
        "aria-label",
        translate("list_detail.uncheck_item", { name: item.name }, "Uncheck {name}")
      );
      main.appendChild(checkButton);

      const copy = document.createElement("div");
      copy.className = "item-copy";

      const title = document.createElement("h3");
      title.className = "item-name";
      title.textContent = item.name;
      copy.appendChild(title);

      if (item.quantity_text) {
        const quantity = document.createElement("p");
        quantity.className = "item-meta";
        quantity.textContent = translate("list_detail.quantity_prefix", { quantity: item.quantity_text }, "Qty: {quantity}");
        copy.appendChild(quantity);
      }

      if (item.note) {
        const note = document.createElement("p");
        note.className = "item-meta";
        note.textContent = item.note;
        copy.appendChild(note);
      }

      main.appendChild(copy);
      cardContent.appendChild(main);
      article.appendChild(cardContent);
      section.appendChild(article);
    });

    if (state.checkedRemainingCount > 0) {
      const remainingCount = state.checkedRemainingCount;
      const loadMoreWrapper = document.createElement("div");
      loadMoreWrapper.className = "checked-items-load-more";

      const loadMoreButton = document.createElement("button");
      loadMoreButton.type = "button";
      loadMoreButton.className = "secondary-button";
      loadMoreButton.textContent = `Load ${Math.min(CHECKED_ITEMS_LOAD_MORE_COUNT, remainingCount)} more`;
      loadMoreButton.addEventListener("click", async () => {
        loadMoreButton.disabled = true;
        try {
          await loadMoreCheckedItems(root, state);
        } finally {
          loadMoreButton.disabled = false;
        }
      });
      loadMoreWrapper.appendChild(loadMoreButton);

      const loadMoreMeta = document.createElement("p");
      loadMoreMeta.className = "item-category-meta";
      loadMoreMeta.textContent = `${remainingCount} older ${remainingCount === 1 ? "item" : "items"} not loaded`;
      loadMoreWrapper.appendChild(loadMoreMeta);

      section.appendChild(loadMoreWrapper);
    }

    container.appendChild(section);
  }

  renderItemSuggestions(root, state);
  renderCategoryOrderSettings(root, state);
  if (state.editingItemId && !isItemEditDraftDirty(root, state)) {
    setItemEditPanelOpen(root, state, state.editingItemId);
  } else if (state.editingItemId) {
    updateItemEditUndoButton(root, state);
  }
}

function replaceItems(state, items) {
  state.items = new Map(items.map((item) => [item.id, item]));
}

function upsertItem(state, item) {
  state.items.set(item.id, item);
}

function removeItem(state, itemId) {
  state.items.delete(itemId);
}

async function loadMoreCheckedItems(root, state) {
  if (isDemoList(root)) {
    return [];
  }

  const listId = root.dataset.listId;
  const checkedOffset = [...state.items.values()].filter((item) => item.checked).length;
  const olderItems = await fetchJson(
    `/api/v1/lists/${listId}/items/checked?offset=${checkedOffset}&limit=${CHECKED_ITEMS_LOAD_MORE_COUNT}`,
  );
  olderItems.forEach((item) => {
    state.items.set(item.id, item);
  });
  state.checkedRemainingCount = Math.max((state.checkedRemainingCount || 0) - olderItems.length, 0);
  renderItems(root, state);
  return olderItems;
}

async function setItemHiddenUntil(root, state, itemId, hiddenUntil) {
  const updatedItem = await updateItemWithOfflineFallback(root, state, itemId, {
    hidden_until: hiddenUntil,
  });
  upsertItem(state, updatedItem);
  renderItems(root, state);
  persistOfflineListState(root, state);
  return updatedItem;
}

async function restoreHiddenItem(root, state, itemId) {
  return setItemHiddenUntil(root, state, itemId, null);
}

async function hideItemForLater(root, state, itemId, nowMs = Date.now()) {
  const hiddenUntil = new Date(nowMs + ITEM_HIDE_DURATION_MS).toISOString();
  const updatedItem = await setItemHiddenUntil(root, state, itemId, hiddenUntil);
  showUndoToast(
    root,
    state,
    translate("list_detail.item_hidden_named", { name: updatedItem.name }, "{name} hidden for 4 hours."),
    restoreHiddenItem.bind(null, root, state, itemId),
  );
  return updatedItem;
}

async function restoreCheckedSuggestion(root, state, reuseItemId) {
  const revertedItem = await setItemCheckedWithOfflineFallback(root, state, reuseItemId, true);
  upsertItem(state, revertedItem);
  renderItems(root, state);
  persistOfflineListState(root, state);
}

async function restoreDeletedItem(root, state, listId, deletedItem) {
  const restoredItem = await createItemWithOfflineFallback(root, state, listId, {
    name: deletedItem.name,
    quantity_text: deletedItem.quantity_text,
    note: deletedItem.note,
    category_id: deletedItem.category_id,
    sort_order: deletedItem.sort_order,
  });
  let nextItem = restoredItem;
  if (deletedItem.checked) {
    nextItem = await setItemCheckedWithOfflineFallback(root, state, restoredItem.id, true);
  }
  upsertItem(state, nextItem);
  renderItems(root, state);
  persistOfflineListState(root, state);
}

async function deleteItem(root, state, listId, itemId) {
  const deletedItem = state.items.get(itemId);
  if (!deletedItem) {
    throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
  }

  const queueDelete = () => {
    queueOfflineMutation(
      root,
      state,
      {
        mutation_id: createOfflineId(OFFLINE_MUTATION_ID_PREFIX),
        type: "delete",
        item_id: itemId,
        recorded_at: new Date().toISOString(),
      },
      () => {
        removeItem(state, itemId);
        return null;
      },
    );
  };

  if (!isDemoList(root) && shouldQueueItemMutation(state, itemId)) {
    queueDelete();
  } else if (!isDemoList(root)) {
    try {
      const response = await fetch(`/api/v1/items/${itemId}`, { method: "DELETE" });
      if (response.status === 401) {
        navigateTo("/login");
        throw new Error(translate("common.errors.unauthorized", {}, "Unauthorized"));
      }
      if (!response.ok) {
        throw new Error(translate("list_detail.item_delete_failed", {}, "Could not delete item."));
      }
    } catch (error) {
      if (!isOfflineRequestError(error)) {
        throw error;
      }
      queueDelete();
    }
  }

  removeItem(state, itemId);
  renderItems(root, state);
  persistOfflineListState(root, state);
  showUndoToast(
    root,
    state,
    translate("list_detail.item_deleted_named", { name: deletedItem.name }, "{name} deleted."),
    restoreDeletedItem.bind(null, root, state, listId, deletedItem),
  );
  if (state.editingItemId === itemId) {
    setItemEditPanelOpen(root, state, null);
  }
  if (state.pendingMutations.length > 0) {
    showOfflineSavedMessage(root);
  } else {
    setListMessage(root, "success", translate("list_detail.item_deleted", {}, "Item deleted."));
  }
}

async function restoreToggledItem(root, state, toggleId, action) {
  const revertedItem = await setItemCheckedWithOfflineFallback(root, state, toggleId, action !== "check");
  upsertItem(state, revertedItem);
  renderItems(root, state);
  persistOfflineListState(root, state);
}

function handleSocketClose(root, state, reconnect, isDisposed) {
  state.socket = null;
  if (isDisposed()) {
    return;
  }
  setListSyncStatus(root, translate("list_detail.sync_paused", {}, "Live updates paused. Reconnecting..."));
  window.setTimeout(reconnect, 1500);
}

function disposeSocket(state, markDisposed) {
  markDisposed();
  if (typeof state.socket?.close === "function") {
    state.socket.close();
  }
}

async function loadListDetail(root, state) {
  if (isDemoList(root)) {
    const payload = state.demoPayload || getDemoPayload(root);
    if (!payload?.list || !payload?.item_window) {
      throw new Error(translate("list_detail.load_failed", {}, "Could not load the list."));
    }

    setListName(root, state, payload.list.name);
    renderListSwitcher(root, payload.list, []);

    const categories = Array.isArray(payload.categories) ? payload.categories : [];
    const categoryOrder = Array.isArray(payload.category_order) ? payload.category_order : [];
    const disabledCategoryIds = Array.isArray(payload.disabled_category_ids)
      ? payload.disabled_category_ids
      : [];
    const items = Array.isArray(payload.item_window.items) ? payload.item_window.items : [];

    state.demoPayload = payload;
    state.nextDemoId = items.length + 1;
    state.lists = [{ id: payload.list.id, name: payload.list.name }];
    state.categories = new Map(categories.map((category) => [category.id, category]));
    state.categoryOrder = new Map(categoryOrder.map((entry) => [entry.category_id, entry.sort_order]));
    setDisabledCategoryIds(state, disabledCategoryIds);
    replaceItems(state, items.map(cloneDemoItem));
    state.checkedRemainingCount = payload.item_window.checked_remaining_count || 0;
    syncCategoryRadioGroups(root, state);
    renderItems(root, state);
    return;
  }

  const listId = root.dataset.listId;
  let groceryList;
  let itemWindow;
  let categories;
  let categoryOrder;
  let disabledCategories;
  let switchTargets = [];

  try {
    groceryList = await fetchJson(`/api/v1/lists/${listId}`);
    [itemWindow, categories, categoryOrder, disabledCategories, switchTargets] = await Promise.all([
      fetchJson(`/api/v1/lists/${listId}/items/window`),
      fetchJson(`/api/v1/lists/${listId}/categories`),
      fetchJson(`/api/v1/lists/${listId}/category-order`),
      fetchJson(`/api/v1/lists/${listId}/disabled-categories`),
      loadListSwitchTargets().catch(() => []),
    ]);
  } catch (error) {
    const cachedState = loadOfflineListState(listId);
    if (cachedState) {
      applyOfflineListState(root, state, cachedState);
      renderListSwitcher(root, null, []);
      setListMessage(
        root,
        "error",
        translate("list_detail.offline_showing_saved", {}, "Offline. Showing saved list."),
      );
      setListSyncStatus(
        root,
        translate("list_detail.offline_sync_pending", {}, "Changes saved locally."),
      );
      return;
    }
    throw error;
  }

  setListName(root, state, groceryList.name);
  renderListSwitcher(root, groceryList, switchTargets);

  state.categories = new Map(categories.map((category) => [category.id, category]));
  state.lists = switchTargets.filter((list) => list.household_id === groceryList.household_id);
  state.categoryOrder = new Map(
    categoryOrder.map((entry) => [entry.category_id, entry.sort_order])
  );
  setDisabledCategoryIds(state, disabledCategories.category_ids || []);
  state.pendingMutations = [];
  const cachedState = loadOfflineListState(listId);
  if (cachedState?.pendingMutations?.length > 0 && Array.isArray(cachedState.items)) {
    state.pendingMutations = cachedState.pendingMutations;
    replaceItems(state, cachedState.items);
    state.checkedRemainingCount = cachedState.checkedRemainingCount || 0;
  } else {
    replaceItems(state, itemWindow.items || []);
    state.checkedRemainingCount = itemWindow.checked_remaining_count || 0;
  }
  syncCategoryRadioGroups(root, state);
  renderItems(root, state);
  persistOfflineListState(root, state);
  await flushOfflineMutations(root, state);
}

function connectListSocket(root, state) {
  if (isDemoList(root)) {
    setListSyncStatus(
      root,
      root.dataset.demoSyncText || translate("list_detail.sync_unavailable", {}, "Live updates unavailable.")
    );
    return;
  }

  const listId = root.dataset.listId;
  if (!listId) {
    setListSyncStatus(root, translate("list_detail.sync_unavailable", {}, "Live updates unavailable."));
    return;
  }

  let isDisposed = false;

  const connect = () => {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const socketUrl = `${protocol}//${window.location.host}/api/v1/ws/lists/${listId}`;
    setListSyncStatus(root, translate("list_detail.sync_connecting", {}, "Connecting live updates..."));
    state.socket = new WebSocket(socketUrl);

    if (typeof state.socket?.addEventListener !== "function") {
      setListSyncStatus(root, translate("list_detail.sync_unavailable", {}, "Live updates unavailable."));
      return;
    }

    state.socket.addEventListener("open", () => {
      setListSyncStatus(root, translate("list_detail.sync_on", {}, "Live updates on."));
      flushOfflineMutations(root, state);
    });

    state.socket.addEventListener("message", (event) => {
      if (state.pendingMutations.length > 0) {
        return;
      }

      const message = JSON.parse(event.data);
      if (message.type === "list_snapshot") {
        replaceItems(state, message.payload.items || []);
        state.checkedRemainingCount = message.payload.checked_remaining_count || 0;
        state.categoryOrder = new Map(
          (message.payload.category_order || []).map((entry) => [entry.category_id, entry.sort_order])
        );
        setDisabledCategoryIds(state, message.payload.disabled_category_ids || []);
        syncCategoryRadioGroups(root, state);
        renderItems(root, state);
        return;
      }

      if (message.type === "category_order_updated") {
        state.categoryOrder = new Map(
          (message.payload?.category_order || []).map((entry) => [entry.category_id, entry.sort_order])
        );
        renderItems(root, state);
        renderCategoryOrderSettings(root, state);
        return;
      }

      if (message.type === "category_disabled_categories_updated") {
        setDisabledCategoryIds(state, message.payload?.category_ids || []);
        syncCategoryRadioGroups(root, state);
        renderItems(root, state);
        renderCategoryOrderSettings(root, state);
        persistOfflineListState(root, state);
        return;
      }

      const item = message.payload?.item;
      if (message.type === "item_deleted") {
        if (item?.id) {
          removeItem(state, item.id);
          renderItems(root, state);
        }
        return;
      }

      if (!item) {
        return;
      }

      upsertItem(state, item);
      renderItems(root, state);
    });

    state.socket.addEventListener("close", () => {
      handleSocketClose(root, state, connect, () => isDisposed);
    });
  };

  connect();
  window.addEventListener("beforeunload", () => {
    disposeSocket(state, () => {
      isDisposed = true;
    });
  });
}

async function initListDetail() {
  const root = document.querySelector("[data-list-detail]");
  if (!root) {
    return;
  }

  const itemForm = root.querySelector("[data-item-form]");
  const itemEditForm = root.querySelector("[data-item-edit-form]");
  const nameInput = root.querySelector("[data-item-name-input]");
  const listId = root.dataset.listId;
  const state = {
    categoryOrder: new Map(),
    categories: new Map(),
    checkedRemainingCount: 0,
    demoPayload: getDemoPayload(root),
    disabledCategoryIds: new Set(),
    editingItemId: null,
    highlightedItemId: null,
    highlightTimers: new Map(),
    itemEditHistory: loadItemEditHistory(listId),
    itemEditLastSavedPayload: null,
    itemEditNeedsSave: false,
    itemEditRedoHistory: loadItemEditRedoHistory(listId),
    itemEditSaveInFlight: null,
    itemEditSaveTimerId: null,
    items: new Map(),
    lists: [],
    listName: "",
    movedItemNotices: new Map(),
    nextDemoId: 1,
    offlineSyncInFlight: null,
    openItemMenuId: null,
    pendingMutations: [],
    socket: null,
    suppressNextClick: false,
    swipeGesture: null,
    undoAction: null,
    undoTimerId: null,
  };

  const refresh = async () => {
    setListMessage(root, "", "");
    await loadListDetail(root, state);
  };

  const shouldOpenItemPanelFromQuery = () => {
    const params = new URLSearchParams(window.location.search);
    return params.get("addItem") === "1";
  };

  const clearItemPanelQuery = () => {
    const url = new URL(window.location.href);
    url.searchParams.delete("addItem");
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  };

  bindListSwitcher(root);

  root.querySelectorAll("[data-item-form-toggle]").forEach((toggle) => {
    toggle.addEventListener("click", () => {
      const panel = root.querySelector("[data-item-panel]");
      setItemPanelOpen(root, panel?.hidden ?? true);
      renderItemSuggestions(root, state);
    });
  });

  root.querySelectorAll("[data-item-form-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setItemPanelOpen(root, false);
    });
  });

  root.querySelectorAll("[data-item-edit-close]").forEach((node) => {
    node.addEventListener("click", () => {
      void closeItemEditPanel(root, state);
    });
  });

  root.querySelector("[data-list-settings-toggle]")?.addEventListener("click", () => {
    const panel = root.querySelector("[data-list-settings-panel]");
    setListSettingsOpen(root, state, panel instanceof HTMLElement ? panel.hidden : true);
  });

  root.querySelectorAll("[data-list-settings-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setListSettingsOpen(root, state, false);
    });
  });

  root.querySelector("[data-list-name-form]")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const input = root.querySelector("[data-list-name-input]");
    const submitButton = root.querySelector("[data-list-name-submit]");
    submitButton.disabled = true;
    try {
      await saveListName(root, state, input.value);
      setListMessage(
        root,
        "success",
        translate("list_detail.list_name_saved", {}, "List name saved."),
      );
    } catch (error) {
      setListMessage(
        root,
        "error",
        error instanceof Error
          ? error.message
          : translate("list_detail.list_name_save_failed", {}, "Could not save list name."),
      );
    } finally {
      submitButton.disabled = false;
    }
  });

  nameInput?.addEventListener("input", () => {
    renderItemSuggestions(root, state);
  });

  root.querySelector("[data-item-category-search]")?.addEventListener("input", () => {
    syncCategoryRadioGroups(root, state);
  });

  root.querySelector("[data-item-edit-category-search]")?.addEventListener("input", () => {
    syncCategoryRadioGroups(root, state);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }

    const settingsPanel = root.querySelector("[data-list-settings-panel]");
    if (settingsPanel instanceof HTMLElement && !settingsPanel.hidden) {
      setListSettingsOpen(root, state, false);
      return;
    }

    if (state.editingItemId) {
      void closeItemEditPanel(root, state);
      return;
    }

    const panel = root.querySelector("[data-item-panel]");
    if (panel instanceof HTMLElement && !panel.hidden) {
      setItemPanelOpen(root, false);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" || event.defaultPrevented) {
      return;
    }

    const activeElement = document.activeElement;
    const panel = root.querySelector("[data-item-panel]");
    const editOverlay = root.querySelector("[data-item-edit-overlay]");
    const isTypingContext =
      activeElement instanceof HTMLInputElement ||
      activeElement instanceof HTMLTextAreaElement ||
      activeElement instanceof HTMLSelectElement ||
      activeElement?.isContentEditable;

    if (
      isTypingContext ||
      !panel?.hidden ||
      (editOverlay instanceof HTMLElement && !editOverlay.hidden)
    ) {
      return;
    }

    event.preventDefault();
    setItemPanelOpen(root, true);
    renderItemSuggestions(root, state);
  });

  root.querySelector("[data-list-toast-undo]")?.addEventListener("click", async () => {
    if (!state.undoAction) {
      return;
    }

    const undoAction = state.undoAction;
    hideUndoToast(root, state);

    await runUndoAction(root, state, undoAction);
  });

  itemEditForm?.addEventListener("input", (event) => {
    const target = event.target;
    if (
      target instanceof HTMLInputElement &&
      ["name", "quantity_text", "note"].includes(target.name)
    ) {
      scheduleItemEditSave(root, state);
    }
  });

  itemEditForm?.addEventListener("focusout", (event) => {
    const target = event.target;
    const relatedTarget = event.relatedTarget;
    if (
      relatedTarget instanceof HTMLElement &&
      relatedTarget.closest("[data-item-edit-close], [data-item-edit-delete], [data-item-edit-redo], [data-item-edit-undo]")
    ) {
      return;
    }
    if (
      target instanceof HTMLInputElement &&
      ["name", "quantity_text", "note"].includes(target.name)
    ) {
      void flushItemEditSave(root, state);
    }
  });

  itemEditForm?.addEventListener("change", (event) => {
    const target = event.target;
    if (target instanceof HTMLInputElement && target.name === "edit_category_id") {
      void flushItemEditSave(root, state);
      return;
    }
    if (target instanceof HTMLSelectElement && target.name === "list_id") {
      void moveEditingItemToList(root, state, target.value);
    }
  });

  itemEditForm?.addEventListener("submit", (event) => {
    event.preventDefault();
    void flushItemEditSave(root, state);
  });

  root.querySelector("[data-item-edit-undo]")?.addEventListener("click", () => {
    void undoItemEdit(root, state);
  });

  root.querySelector("[data-item-edit-redo]")?.addEventListener("click", () => {
    void redoItemEdit(root, state);
  });

  if (typeof window !== "undefined") {
    window.addEventListener("online", () => {
      flushOfflineMutations(root, state);
    });
  }

  root.addEventListener("pointerdown", (event) => {
    if (!(event.target instanceof HTMLElement) || event.target.closest("button")) {
      return;
    }

    const card = event.target.closest("[data-item-card]");
    if (
      !(card instanceof HTMLElement) ||
      card.classList.contains("is-checked") ||
      card.classList.contains("is-hidden")
    ) {
      return;
    }

    state.swipeGesture = {
      card,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      offsetX: 0,
      locked: false,
    };
    try {
      card.setPointerCapture?.(event.pointerId);
    } catch {
      // Synthetic pointer events in browser tests do not always register as active pointers.
    }
  });

  root.addEventListener("pointermove", (event) => {
    const gesture = state.swipeGesture;
    if (!gesture || gesture.pointerId !== event.pointerId) {
      return;
    }

    const deltaX = Math.max(0, event.clientX - gesture.startX);
    const deltaY = Math.abs(event.clientY - gesture.startY);
    if (!gesture.locked && deltaY > 64 && deltaY > deltaX * 1.5) {
      gesture.card.style.removeProperty("--item-swipe-x");
      gesture.card.classList.remove("is-swiping", "is-swipe-ready");
      state.swipeGesture = null;
      return;
    }

    if (deltaX <= 4) {
      return;
    }

    if (deltaX > 16) {
      gesture.locked = true;
    }
    gesture.offsetX = Math.min(deltaX, ITEM_SWIPE_LIMIT_PX);
    gesture.card.style.setProperty("--item-swipe-x", `${gesture.offsetX}px`);
    gesture.card.classList.add("is-swiping");
    gesture.card.classList.toggle("is-swipe-ready", gesture.offsetX >= ITEM_SWIPE_TRIGGER_PX);
    event.preventDefault();
  });

  root.addEventListener("pointerup", async (event) => {
    const gesture = state.swipeGesture;
    if (!gesture || gesture.pointerId !== event.pointerId) {
      return;
    }

    state.swipeGesture = null;
    try {
      gesture.card.releasePointerCapture?.(event.pointerId);
    } catch {
      // Matching the tolerant capture path above.
    }
    gesture.card.classList.remove("is-swiping", "is-swipe-ready");
    gesture.card.style.removeProperty("--item-swipe-x");

    if (gesture.offsetX < ITEM_SWIPE_TRIGGER_PX) {
      return;
    }

    state.suppressNextClick = true;
    window.setTimeout(() => {
      state.suppressNextClick = false;
    }, 0);
    try {
      await hideItemForLater(root, state, gesture.card.dataset.itemCard);
    } catch (error) {
      setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.list_action_failed", {}, "List action failed."));
    }
  });

  root.addEventListener("pointercancel", (event) => {
    const gesture = state.swipeGesture;
    if (!gesture || gesture.pointerId !== event.pointerId) {
      return;
    }

    state.swipeGesture = null;
    gesture.card.classList.remove("is-swiping", "is-swipe-ready");
    gesture.card.style.removeProperty("--item-swipe-x");
  });

  itemForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(itemForm);
    const name = String(formData.get("name") || "").trim();
    if (!name) {
      setListMessage(root, "error", translate("list_detail.item_name_required", {}, "Please enter an item name."));
      return;
    }

    const payload = { name };
    const categoryId = String(formData.get("category_id") || "").trim();
    const quantityText = String(formData.get("quantity_text") || "").trim();
    const note = String(formData.get("note") || "").trim();
    if (categoryId) {
      payload.category_id = categoryId;
    }
    if (quantityText) {
      payload.quantity_text = quantityText;
    }
    if (note) {
      payload.note = note;
    }

    try {
      const createdItem = await createItemWithOfflineFallback(root, state, listId, payload);
      upsertItem(state, createdItem);
      itemForm.reset();
      const addSearch = root.querySelector("[data-item-category-search]");
      if (addSearch instanceof HTMLInputElement) {
        addSearch.value = "";
      }
      setCategoryRadioValue(root, 'input[name="category_id"]', "");
      syncCategoryRadioGroups(root, state);
      renderItems(root, state);
      persistOfflineListState(root, state);
      setItemPanelOpen(root, false);
      highlightItem(root, state, createdItem.id);
      hideUndoToast(root, state);
      if (state.pendingMutations.length > 0) {
        showOfflineSavedMessage(root);
      } else {
        setListMessage(root, "success", translate("list_detail.item_added", {}, "Item added."));
      }
    } catch (error) {
      setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.item_add_failed", {}, "Could not add item."));
    }
  });

  root.addEventListener("click", async (event) => {
    const eventTarget = event.target;
    if (!(eventTarget instanceof Element)) {
      return;
    }

    const actionTarget = eventTarget.closest(
      "[data-item-toggle], [data-item-hide], [data-item-unhide], [data-item-menu-toggle], [data-item-reuse], [data-moved-item-undo], [data-settings-category-move], [data-settings-category-toggle]"
    );
    const target = actionTarget instanceof HTMLElement ? actionTarget : null;
    const toggleId = target?.dataset.itemToggle || "";
    const hideId = target?.dataset.itemHide || "";
    const unhideId = target?.dataset.itemUnhide || "";
    const menuToggleId = target?.dataset.itemMenuToggle || "";
    const reuseItemId = target?.dataset.itemReuse || "";
    const movedItemUndoId = target?.dataset.movedItemUndo || "";
    const categoryMove = target?.dataset.settingsCategoryMove || "";
    const categoryToggleId = target?.dataset.settingsCategoryToggle || "";
    const categoryId = target?.dataset.categoryId || "";
    const quickAddButton = eventTarget.closest("[data-item-quick-add-category]");
    const editCard = eventTarget.closest("[data-item-edit]");

    if (state.suppressNextClick) {
      state.suppressNextClick = false;
      return;
    }

    if (quickAddButton instanceof HTMLElement) {
      event.preventDefault();
      openItemPanelForCategory(root, state, quickAddButton.dataset.itemQuickAddCategory || "");
      return;
    }

    if (editCard && !eventTarget.closest("button")) {
      setItemEditPanelOpen(root, state, editCard.dataset.itemEdit || null);
      return;
    }

    if (
      !toggleId &&
      !hideId &&
      !unhideId &&
      !menuToggleId &&
      !reuseItemId &&
      !movedItemUndoId &&
      !categoryMove &&
      !categoryToggleId
    ) {
      return;
    }

    try {
      if (categoryToggleId) {
        const didChange = await setCategoryDisabled(
          root,
          state,
          categoryToggleId,
          !isCategoryDisabled(state, categoryToggleId),
        );
        if (didChange) {
          setListMessage(root, "success", translate("list_detail.category_settings_saved", {}, "Category settings saved."));
        }
        return;
      }

      if (categoryMove && categoryId) {
        const orderedCategoryIds = getOrderedCategoryIds(state);
        const currentIndex = orderedCategoryIds.indexOf(categoryId);
        if (currentIndex === -1) {
          return;
        }

        const nextIndex = categoryMove === "up" ? currentIndex - 1 : currentIndex + 1;
        if (nextIndex < 0 || nextIndex >= orderedCategoryIds.length) {
          return;
        }

        const nextOrderedCategoryIds = reorderCategoryIds(orderedCategoryIds, categoryId, nextIndex);

        setCategoryOrder(state, deriveManualCategoryIds(state, nextOrderedCategoryIds));
        renderItems(root, state);
        renderCategoryOrderSettings(root, state);
        persistOfflineListState(root, state);
        saveCategoryOrderInBackground(root, state);
        return;
      }

      if (menuToggleId) {
        state.openItemMenuId = state.openItemMenuId === menuToggleId ? null : menuToggleId;
        renderItems(root, state);
        return;
      }

      if (hideId) {
        state.openItemMenuId = null;
        await hideItemForLater(root, state, hideId);
        return;
      }

      if (unhideId) {
        const restoredItem = await restoreHiddenItem(root, state, unhideId);
        highlightItem(root, state, restoredItem.id);
        return;
      }

      if (reuseItemId) {
        const existingItem = state.items.get(reuseItemId);
        if (!existingItem) {
          throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
        }
        if (existingItem.checked) {
          const updatedItem = await setItemCheckedWithOfflineFallback(root, state, reuseItemId, false);
          upsertItem(state, updatedItem);
          itemForm.reset();
          renderItems(root, state);
          persistOfflineListState(root, state);
          setItemPanelOpen(root, false);
          highlightItem(root, state, reuseItemId);
          showUndoToast(
            root,
            state,
            translate("list_detail.item_added_back_named", { name: existingItem.name }, "{name} added back to the list."),
            restoreCheckedSuggestion.bind(null, root, state, reuseItemId),
          );
          if (state.pendingMutations.length > 0) {
            showOfflineSavedMessage(root);
          } else {
            setListMessage(root, "success", translate("list_detail.item_added_back", {}, "Item added back to the list."));
          }
          return;
        }

        setItemPanelOpen(root, false);
        highlightItem(root, state, reuseItemId);
        return;
      }

      if (movedItemUndoId) {
        await restoreMovedItem(root, state, movedItemUndoId);
        return;
      }

      if (toggleId) {
        const existingItem = state.items.get(toggleId);
        if (!existingItem) {
          throw new Error(translate("list_detail.item_not_found", {}, "Could not find that item."));
        }
        const action = existingItem.checked ? "uncheck" : "check";
        const updatedItem = await setItemCheckedWithOfflineFallback(root, state, toggleId, action === "check");
        upsertItem(state, updatedItem);
        renderItems(root, state);
        persistOfflineListState(root, state);
        showUndoToast(
          root,
          state,
          action === "check"
            ? translate("list_detail.item_checked_named", { name: existingItem.name }, "{name} checked.")
            : translate("list_detail.item_unchecked_named", { name: existingItem.name }, "{name} unchecked."),
          restoreToggledItem.bind(null, root, state, toggleId, action),
        );
        return;
      }
    } catch (error) {
      setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.list_action_failed", {}, "List action failed."));
    }
  });

  root.addEventListener("pointerdown", (event) => {
    const eventTarget = event.target;
    if (!(eventTarget instanceof Element)) {
      return;
    }
    const grabber = eventTarget.closest("[data-settings-category-grabber]");
    const row = grabber?.closest(".settings-category-row");
    if (!(row instanceof HTMLElement) || !row.dataset.categoryId) {
      return;
    }

    event.preventDefault();
    state.pointerCategoryDrag = {
      categoryId: row.dataset.categoryId,
      pointerId: event.pointerId,
    };
    row.classList.add("is-dragging");
    if (grabber instanceof HTMLElement) {
      try {
        grabber.setPointerCapture?.(event.pointerId);
      } catch {
        // Some synthetic test pointers do not support capture.
      }
    }
  });

  root.addEventListener("pointermove", (event) => {
    const drag = state.pointerCategoryDrag;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }

    event.preventDefault();
    const elementAtPoint = document.elementFromPoint?.(event.clientX, event.clientY);
    const row = elementAtPoint?.closest?.(".settings-category-row");
    if (!(row instanceof HTMLElement) || row.dataset.categoryId === drag.categoryId) {
      state.categoryDropTarget = null;
      clearCategoryDropIndicators(root);
      return;
    }

    setCategoryDropIndicator(root, state, row, categoryDropPosition(row, event.clientY));
  });

  root.addEventListener("pointerup", (event) => {
    const drag = state.pointerCategoryDrag;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }

    event.preventDefault();
    const dropTarget = state.categoryDropTarget;
    state.pointerCategoryDrag = null;
    state.categoryDropTarget = null;
    if (dropTarget) {
      applyCategoryReorder(
        root,
        state,
        drag.categoryId,
        dropTarget.categoryId,
        dropTarget.position
      );
    }
    clearCategoryDragState(root);
  });

  root.addEventListener("pointercancel", (event) => {
    const drag = state.pointerCategoryDrag;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }

    state.pointerCategoryDrag = null;
    state.categoryDropTarget = null;
    clearCategoryDragState(root);
  });

  root.addEventListener("dragstart", (event) => {
    const eventTarget = event.target;
    if (!(eventTarget instanceof Element)) {
      return;
    }
    const grabber = eventTarget.closest("[data-settings-category-grabber]");
    const row = grabber?.closest(".settings-category-row");
    if (!(row instanceof HTMLElement) || !row.dataset.categoryId) {
      return;
    }

    state.draggingCategoryId = row.dataset.categoryId;
    row.classList.add("is-dragging");
    event.dataTransfer?.setData("text/plain", row.dataset.categoryId);
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
    }
  });

  root.addEventListener("dragover", (event) => {
    if (!state.draggingCategoryId) {
      return;
    }
    const eventTarget = event.target;
    if (!(eventTarget instanceof Element)) {
      return;
    }
    const row = eventTarget.closest(".settings-category-row");
    if (!(row instanceof HTMLElement) || row.dataset.categoryId === state.draggingCategoryId) {
      return;
    }

    event.preventDefault();
    setCategoryDropIndicator(root, state, row, categoryDropPosition(row, event.clientY));
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "move";
    }
  });

  root.addEventListener("drop", async (event) => {
    const eventTarget = event.target;
    if (!(eventTarget instanceof Element)) {
      return;
    }
    const row = eventTarget.closest(".settings-category-row");
    const draggedCategoryId =
      state.draggingCategoryId || event.dataTransfer?.getData("text/plain") || "";
    if (!(row instanceof HTMLElement) || !row.dataset.categoryId || !draggedCategoryId) {
      clearCategoryDragState(root);
      return;
    }

    event.preventDefault();
    const orderedCategoryIds = getOrderedCategoryIds(state);
    const currentIndex = orderedCategoryIds.indexOf(draggedCategoryId);
    const targetIndex = orderedCategoryIds.indexOf(row.dataset.categoryId);
    if (currentIndex === -1 || targetIndex === -1 || currentIndex === targetIndex) {
      clearCategoryDragState(root);
      return;
    }

    const didReorder = applyCategoryReorder(
      root,
      state,
      draggedCategoryId,
      row.dataset.categoryId,
      categoryDropPosition(row, event.clientY)
    );
    if (!didReorder) {
      clearCategoryDragState(root);
      return;
    }

    state.draggingCategoryId = null;
    state.categoryDropTarget = null;
    clearCategoryDragState(root);
  });

  root.addEventListener("dragend", () => {
    state.draggingCategoryId = null;
    clearCategoryDragState(root);
  });

  root.querySelector("[data-item-edit-delete]")?.addEventListener("click", async () => {
    if (!state.editingItemId) {
      return;
    }

    try {
      cancelItemEditSaveTimer(state);
      await deleteItem(root, state, listId, state.editingItemId);
    } catch (error) {
      setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.item_delete_failed", {}, "Could not delete item."));
    }
  });

  try {
    await refresh();
    if (shouldOpenItemPanelFromQuery()) {
      setItemPanelOpen(root, true);
      renderItemSuggestions(root, state);
      clearItemPanelQuery();
    }
    connectListSocket(root, state);
  } catch (error) {
    setListMessage(root, "error", error instanceof Error ? error.message : translate("list_detail.load_failed", {}, "Could not load the list."));
  }
}

async function registerWithPasskey(root, form) {
  const formData = new FormData(form);
  const options = await postJson("/api/v1/auth/register/options", {
    email: formData.get("email"),
    display_name: formData.get("display_name"),
  });
  const credential = await navigator.credentials.create({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson("/api/v1/auth/register/verify", {
    credential: credentialToJSON(credential),
  });
  setMessage(root, "success", translate("auth.login.created_redirect", {}, "Passkey created. Redirecting to your dashboard..."));
  navigateTo(root.getAttribute("data-next-url") || "/");
}

async function loginWithPasskey(root, form) {
  void form;
  const options = await postJson("/api/v1/auth/login/options", {});
  const credential = await navigator.credentials.get({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson("/api/v1/auth/login/verify", {
    credential: credentialToJSON(credential),
  });
  setMessage(root, "success", translate("auth.login.accepted_redirect", {}, "Passkey accepted. Redirecting to your dashboard..."));
  navigateTo(root.getAttribute("data-next-url") || "/");
}

async function addPasskeyWithLink(root) {
  const token = root.getAttribute("data-passkey-add-token");
  if (!token) {
    throw new Error(translate("auth.passkey_add.missing_token", {}, "Passkey add link is missing."));
  }

  const options = await postJson(`/api/v1/auth/passkey-add/${token}/options`, {});
  const credential = await navigator.credentials.create({
    publicKey: publicKeyFromJSON(options),
  });
  await postJson(`/api/v1/auth/passkey-add/${token}/verify`, {
    credential: credentialToJSON(credential),
  });
  setMessage(root, "success", translate("auth.passkey_add.created_redirect", {}, "Additional passkey created. Redirecting to your dashboard..."));
  navigateTo("/");
}

async function handlePasskeyLoginClick(root, loginForm) {
  toggleButtons(root, true);
  try {
    await loginWithPasskey(root, loginForm);
  } catch (error) {
    setMessage(root, "error", error instanceof Error ? error.message : translate("auth.login.login_failed", {}, "Passkey login failed."));
  } finally {
    toggleButtons(root, false);
  }
}

function transitionAuthPanels(root, updatePanels) {
  const panelGroup = root.querySelector("[data-auth-panels]");
  if (!(panelGroup instanceof HTMLElement)) {
    updatePanels();
    return;
  }

  const beforeHeight = panelGroup.getBoundingClientRect().height;
  updatePanels();
  const afterHeight = panelGroup.scrollHeight;
  if (!beforeHeight || !afterHeight || beforeHeight === afterHeight) {
    return;
  }

  panelGroup.style.height = `${beforeHeight}px`;
  panelGroup.style.overflow = "hidden";
  panelGroup.getBoundingClientRect();
  panelGroup.style.height = `${afterHeight}px`;

  const settle = () => {
    panelGroup.style.height = "";
    panelGroup.style.overflow = "";
    panelGroup.removeEventListener("transitionend", settle);
  };
  panelGroup.addEventListener("transitionend", settle, { once: true });
  window.setTimeout(settle, 240);
}

function setAuthTab(root, tab) {
  const panels = root.querySelectorAll("[data-auth-tab-panel]");
  const triggers = root.querySelectorAll("[data-auth-tab-trigger]");
  if (!panels.length || !triggers.length) {
    return;
  }

  transitionAuthPanels(root, () => {
    panels.forEach((panel) => {
      panel.hidden = panel.getAttribute("data-auth-tab-panel") !== tab;
    });
  });

  triggers.forEach((trigger) => {
    trigger.setAttribute(
      "aria-selected",
      trigger.getAttribute("data-auth-tab-trigger") === tab ? "true" : "false"
    );
  });

  if (tab === "signup") {
    root.querySelector('[data-passkey-register] input[name="display_name"]')?.focus();
  }
}

function initPasskeyAuth() {
  const root = document.querySelector("[data-passkey-auth]");
  if (!root) {
    return;
  }

  if (!window.PublicKeyCredential || !navigator.credentials) {
    setMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
    toggleButtons(root, true);
    return;
  }

  const registerForm = root.querySelector("[data-passkey-register]");
  const loginForm = root.querySelector("[data-passkey-login]");
  root.querySelectorAll("[data-auth-tab-trigger]").forEach((trigger) => {
    trigger.addEventListener("click", () => {
      setAuthTab(root, trigger.getAttribute("data-auth-tab-trigger"));
    });
  });

  registerForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    toggleButtons(root, true);
    try {
      await registerWithPasskey(root, registerForm);
    } catch (error) {
      setMessage(root, "error", error instanceof Error ? error.message : translate("auth.login.registration_failed", {}, "Passkey registration failed."));
    } finally {
      toggleButtons(root, false);
    }
  });

  root.querySelector("[data-passkey-login-button]")?.addEventListener(
    "click",
    handlePasskeyLoginClick.bind(null, root, loginForm)
  );
}

function initPasskeyAddLink() {
  const root = document.querySelector("[data-passkey-add-link]");
  if (!root) {
    return;
  }

  if (!window.PublicKeyCredential || !navigator.credentials) {
    setMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
    toggleButtons(root, true);
    return;
  }

  root.querySelector("[data-passkey-add-link-button]")?.addEventListener("click", async () => {
    toggleButtons(root, true);
    try {
      await addPasskeyWithLink(root);
    } catch (error) {
      setMessage(root, "error", error instanceof Error ? error.message : translate("auth.passkey_add.failed", {}, "Passkey add failed."));
    } finally {
      toggleButtons(root, false);
    }
  });
}

function setSettingsMessage(root, type, message) {
  const errorNode = root.querySelector("[data-settings-error]");
  const successNode = root.querySelector("[data-settings-success]");
  if (!(errorNode instanceof HTMLElement) || !(successNode instanceof HTMLElement)) {
    return;
  }

  errorNode.hidden = true;
  successNode.hidden = true;
  errorNode.textContent = "";
  successNode.textContent = "";

  if (type === "error") {
    errorNode.hidden = false;
    errorNode.textContent = message;
    return;
  }

  successNode.hidden = false;
  successNode.textContent = message;
}

function initUserSettings() {
  const root = document.querySelector("[data-user-settings]");
  if (!root) {
    return;
  }

  applyLanguagePreference();
  syncLanguageSettings(root);
  root.querySelector("[data-language-settings-open]")?.addEventListener("click", () => {
    setLanguageSettingsOpen(root, true);
  });
  root.querySelectorAll("[data-language-settings-close]").forEach((node) => {
    node.addEventListener("click", () => {
      setLanguageSettingsOpen(root, false);
    });
  });
  root.querySelector("[data-language-settings-form]")?.addEventListener("submit", (event) => {
    event.preventDefault();
    const select = root.querySelector("[data-language-settings-select]");
    const preference = storeLanguagePreference(select instanceof HTMLSelectElement ? select.value : "");
    syncLanguageSettings(root);
    setLanguageSettingsOpen(root, false);
    setSettingsMessage(
      root,
      "success",
      translate(
        "settings.language_saved",
        { language: languagePreferenceLabel(preference) },
        "Language set to {language}."
      )
    );
    const url = new URL(window.location.href);
    if (preference) {
      url.searchParams.set("lang", preference);
    } else {
      url.searchParams.delete("lang");
    }
    navigateTo(`${url.pathname}${url.search}${url.hash}`);
  });

  if (!window.PublicKeyCredential || !navigator.credentials) {
    setPasskeyManagementMessage(root, "error", translate("common.errors.unsupported_passkeys", {}, "This browser does not support passkeys."));
    toggleButtons(root, true);
    return;
  }

  initPasskeyManagement(root, {
    setMessage: setPasskeyManagementMessage,
    toggleForms: togglePasskeyManagementForms,
    refreshData: () => loadPasskeyManagementData(root),
  }).catch((error) => {
    setPasskeyManagementMessage(
      root,
      "error",
      error instanceof Error ? error.message : translate("settings.load_failed", {}, "Could not load your passkeys.")
    );
  });
}

function formatInviteExpiry(value) {
  const date = new Date(value);
  return date.toLocaleString(getPreferredLocale(), {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

async function initHouseholdInvite() {
  const root = document.querySelector("[data-household-invite]");
  if (!root) {
    return;
  }

  const token = root.getAttribute("data-invite-token");
  const loadingNode = root.querySelector("[data-invite-loading]");
  const readyNode = root.querySelector("[data-invite-ready]");
  const householdNameNode = root.querySelector("[data-invite-household-name]");
  const expiryNode = root.querySelector("[data-invite-expiry]");
  const membershipNoteNode = root.querySelector("[data-invite-membership-note]");
  const acceptButton = root.querySelector("[data-invite-accept]");

  try {
    const invite = await fetchJson(`/api/v1/households/invites/${token}`);
    loadingNode.hidden = true;
    readyNode.hidden = false;
    householdNameNode.textContent = invite.household_name;
    expiryNode.textContent = translate("invite.expires_on", { date: formatInviteExpiry(invite.expires_at) }, "This link expires on {date}.");
    membershipNoteNode.hidden = !invite.already_member;
  } catch (error) {
    loadingNode.hidden = true;
    setInviteMessage(
      root,
      "error",
      error instanceof Error ? error.message : translate("invite.unavailable", {}, "This invite link is no longer available."),
    );
    return;
  }

  acceptButton.addEventListener("click", async () => {
    acceptButton.disabled = true;
    setInviteMessage(root, "", "");
    try {
      const household = await postJson(`/api/v1/households/invites/${token}/accept`, {});
      setInviteMessage(root, "success", translate("invite.accepted", { household: household.name }, "You joined {household}. Redirecting now..."));
      window.setTimeout(() => {
        navigateTo("/");
      }, 500);
    } catch (error) {
      setInviteMessage(
        root,
        "error",
        error instanceof Error ? error.message : translate("invite.accept_failed", {}, "Could not accept the invite."),
      );
      acceptButton.disabled = false;
    }
  });
}

function initApp() {
  applyLanguagePreference();
  registerServiceWorker().catch(() => undefined);
  initPasskeyAuth();
  initPasskeyAddLink();
  initUserSettings();
  initDashboard();
  initHouseholdInvite();
  initListDetail();
}

if (typeof document !== "undefined") {
  initApp();
}

export {
  base64UrlToBytes,
  bytesToBase64Url,
  getI18nState,
  getCurrentLocale,
  interpolateTranslation,
  translate,
  translatePlural,
  isItemHidden,
  formatHiddenUntilLabel,
  publicKeyFromJSON,
  credentialToJSON,
  normalizeLanguagePreference,
  getBrowserLanguage,
  getStoredLanguagePreference,
  storeLanguagePreference,
  getPreferredLocale,
  applyLanguagePreference,
  languagePreferenceLabel,
  syncLanguageSettings,
  setLanguageSettingsOpen,
  registerServiceWorker,
  navigateTo,
  postJson,
  fetchJson,
  setMessage,
  toggleButtons,
  setDashboardMessage,
  toggleDashboardForms,
  syncDashboardModalState,
  setDashboardPanelOpen,
  updateHouseholdOptions,
  updateDashboardListOptions,
  renderHouseholds,
  loadDashboardData,
  formatPasskeyDate,
  renderPasskeys,
  suggestedPasskeyName,
  setPasskeyNameFormState,
  setPasskeyDeleteConfirmState,
  addPasskey,
  renamePasskey,
  deletePasskey,
  initDashboard,
  setListMessage,
  setListSyncStatus,
  renderListSwitcher,
  loadListSwitchTargets,
  bindListSwitcher,
  itemEditHistoryStorageKey,
  itemEditRedoHistoryStorageKey,
  normalizeItemEditPayload,
  itemEditPayloadFromItem,
  itemEditPayloadsEqual,
  loadItemEditHistory,
  loadItemEditRedoHistory,
  pushItemEditHistory,
  pushItemEditRedoHistory,
  popItemEditHistory,
  popItemEditRedoHistory,
  readItemEditFormPayload,
  setItemEditFormValues,
  setItemEditStatus,
  isItemEditDraftDirty,
  updateItemEditUndoButton,
  cancelItemEditSaveTimer,
  applyItemEditPayload,
  saveItemEditDraft,
  scheduleItemEditSave,
  flushItemEditSave,
  closeItemEditPanel,
  undoItemEdit,
  redoItemEdit,
  offlineListStorageKey,
  loadOfflineListState,
  setListName,
  saveListName,
  createOfflineId,
  isBrowserOffline,
  isOfflineRequestError,
  persistOfflineListState,
  applyOfflineListState,
  showOfflineSavedMessage,
  queueOfflineMutation,
  shouldQueueItemMutation,
  applyOfflineSyncResult,
  flushOfflineMutations,
  hideUndoToast,
  showUndoToast,
  createMovedItemNotice,
  dismissMovedItemNotice,
  showMovedItemNotice,
  restoreMovedItem,
  normalizeItemName,
  normalizeSearchText,
  boundedEditDistance,
  fuzzyItemNameDistance,
  itemSuggestionMatch,
  syncModalState,
  setItemPanelOpen,
  openItemPanelForCategory,
  formatSuggestionMeta,
  categorySortKey,
  decorateItem,
  setCategoryRadioValue,
  categoryMatchesQuery,
  setDisabledCategoryIds,
  getDisabledCategoryIds,
  isCategoryDisabled,
  syncCategoryRadioGroup,
  syncCategoryRadioGroups,
  getManualCategoryIds,
  getAlphabeticalCategoryIds,
  getOrderedCategoryIds,
  getDisplayedCategoryIds,
  deriveManualCategoryIds,
  setCategoryOrder,
  reorderCategoryIds,
  isDemoList,
  getDemoPayload,
  cloneDemoItem,
  createDemoItem,
  updateDemoItem,
  setDemoItemChecked,
  createOfflineItem,
  applyLocalCheckedState,
  createItemWithOfflineFallback,
  updateItemWithOfflineFallback,
  moveItemWithOfflineFallback,
  setItemCheckedWithOfflineFallback,
  saveCategoryOrder,
  syncItemMoveSelect,
  showItemMovedMessage,
  moveEditingItemToList,
  saveCategoryOrderInBackground,
  saveDisabledCategories,
  itemCountForCategory,
  unassignCategoryItems,
  restoreItemCategoryIds,
  categoryDisableConfirmText,
  confirmCategoryDisable,
  setCategoryDisabled,
  createCategoryGrabberIcon,
  createCategoryVisibilityIcon,
  clearCategoryDragState,
  clearCategoryDropIndicators,
  categoryDropPosition,
  setCategoryDropIndicator,
  categoryInsertionIndex,
  applyCategoryReorder,
  setItemEditPanelOpen,
  renderCategoryOrderSettings,
  setListSettingsOpen,
  renderItemSuggestions,
  highlightItem,
  compareActiveItems,
  compareCheckedItems,
  getActiveGroupOrder,
  renderItems,
  replaceItems,
  upsertItem,
  removeItem,
  loadMoreCheckedItems,
  setItemHiddenUntil,
  restoreHiddenItem,
  hideItemForLater,
  restoreToggledItem,
  restoreCheckedSuggestion,
  restoreDeletedItem,
  runUndoAction,
  handleSocketClose,
  disposeSocket,
  loadListDetail,
  connectListSocket,
  initListDetail,
  registerWithPasskey,
  loginWithPasskey,
  addPasskeyWithLink,
  handlePasskeyLoginClick,
  transitionAuthPanels,
  setAuthTab,
  setSettingsMessage,
  initPasskeyAuth,
  initPasskeyAddLink,
  initUserSettings,
  formatInviteExpiry,
  initHouseholdInvite,
  initApp,
};
