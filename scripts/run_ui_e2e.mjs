import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { chromium, devices } from "playwright";

const baseUrl = process.env.PREVIEW_BASE_URL ?? "http://127.0.0.1:8000";
const artifactDir = process.env.PREVIEW_ARTIFACT_DIR ?? "e2e-artifacts/ui-e2e";
const backupDir = process.env.PREVIEW_BACKUP_DIR ?? "e2e-artifacts/backups";
const videoDir = path.join(artifactDir, "videos");
const seedPath = process.env.E2E_SEED_PATH ?? "app/fixtures/review_seed_e2e.json";
const deviceName = process.env.E2E_DEVICE ?? "desktop";
const browserLocale = process.env.E2E_LOCALE ?? "en-US";
const browserTimeZone = process.env.E2E_TIMEZONE ?? "Europe/Berlin";
const privacyEmail = process.env.PRIVACY_EMAIL ?? "privacy@example.com";
const supportEmail = process.env.SUPPORT_EMAIL ?? "support@example.com";
const browserChannel = process.env.E2E_BROWSER_CHANNEL?.trim() || undefined;
const recordVideo = !["0", "false", "no"].includes(
  (process.env.E2E_RECORD_VIDEO ?? "true").trim().toLowerCase(),
);
const knownDevices = new Map([["iphone", "iPhone 13"]]);
const staleBlueAccentTokens = [
  "20, 42, 87",
  "29, 184, 217",
  "79, 105, 129",
  "167, 203, 223",
  "223, 248, 253",
  "245, 251, 253",
];
const seedMainCategoryColors = new Map([
  ["Milch & Eier", "rgb(216, 180, 226)"],
  ["Tiefkuehlkost", "rgb(77, 208, 225)"],
  ["Gemuese", "rgb(126, 217, 87)"],
]);
const seedSettingsCategoryColors = new Map([
  ["Backwaren", "rgb(251, 146, 60)"],
  ["Backzutaten", "rgb(236, 72, 153)"],
  ["Fleisch", "rgb(239, 68, 68)"],
]);

function logStep(message) {
  console.log(`[ui-e2e] ${message}`);
}

async function resetDir(dir) {
  await fs.rm(dir, { recursive: true, force: true });
  await fs.mkdir(dir, { recursive: true });
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

function contextOptions() {
  const preset = knownDevices.get(deviceName);
  if (!preset) {
    const viewport = { width: 1440, height: 1200 };
    return {
      viewport,
      locale: browserLocale,
      timezoneId: browserTimeZone,
      ...(recordVideo ? { recordVideo: { dir: videoDir, size: viewport } } : {}),
    };
  }

  const device = devices[preset];
  assert(device, `Unknown Playwright device preset ${preset}`);
  return {
    ...device,
    locale: browserLocale,
    timezoneId: browserTimeZone,
    ...(recordVideo ? { recordVideo: { dir: videoDir, size: device.viewport } } : {}),
  };
}

function toBase64(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  return normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function loadSeed() {
  const seed = JSON.parse(await fs.readFile(seedPath, "utf8"));
  assert(seed?.e2e, "Expected e2e metadata in seed fixture");
  assert(Array.isArray(seed?.users), "Expected users array in seed fixture");
  assert(Array.isArray(seed?.households), "Expected households array in seed fixture");
  return seed;
}

function fixtureUser(seed, email) {
  const user = seed.users.find((entry) => entry.email === email);
  assert(user, `Expected seeded user ${email}`);
  assert(user.passkey, `Expected seeded passkey for ${email}`);
  assert(user.passkey.private_key_pkcs8_b64, `Expected private key fixture for ${email}`);
  assert(user.passkey.user_handle_b64, `Expected user handle fixture for ${email}`);
  return user;
}

function fixtureAccount(seed, email) {
  const user = seed.users.find((entry) => entry.email === email);
  assert(user, `Expected seeded user ${email}`);
  return user;
}

function fixturePrimaryList(seed) {
  const household = seed.households.find((entry) => entry.name === seed.e2e.primary_household);
  assert(household, `Expected primary household ${seed.e2e.primary_household}`);
  const groceryList = household.lists.find((entry) => entry.name === seed.e2e.primary_list);
  assert(groceryList, `Expected primary list ${seed.e2e.primary_list}`);
  return groceryList;
}

async function apiJson(requestContext, url, options = {}) {
  const target = new URL(url, baseUrl).toString();
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await requestContext.fetch(target, options);
      if (!response.ok()) {
        throw new Error(`Request failed for ${url}: ${response.status()} ${response.statusText()}`);
      }
      return response.json();
    } catch (error) {
      lastError = error;
      if (attempt === 3 || !isTransientApiError(error)) {
        throw error;
      }
      logStep(`Retrying API request after transient failure (${attempt}/3): ${url}`);
      await delay(250 * attempt);
    }
  }
  throw lastError;
}

function isTransientApiError(error) {
  const message = String(error?.message ?? error);
  return /socket hang up|ECONNRESET|ECONNREFUSED|ETIMEDOUT|Target page, context or browser has been closed/u.test(
    message,
  );
}

async function expectVisible(locator, message) {
  await locator.waitFor({ state: "visible" });
  assert(await locator.isVisible(), message);
}

async function expectHidden(locator, message) {
  await locator.waitFor({ state: "hidden" });
  assert(!(await locator.isVisible().catch(() => false)), message);
}

async function expectInViewport(locator, message) {
  await locator.waitFor({ state: "visible" });
  const isInViewport = await locator.evaluate(async (node) => {
    const isFullyVisible = () => {
      const rect = node.getBoundingClientRect();
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
      const viewportWidth = window.innerWidth || document.documentElement.clientWidth;
      return (
        rect.top >= 0 &&
        rect.left >= 0 &&
        rect.bottom <= viewportHeight &&
        rect.right <= viewportWidth
      );
    };
    if (isFullyVisible()) {
      return true;
    }
    await new Promise((resolve) => window.setTimeout(resolve, 800));
    return isFullyVisible();
  });
  assert(isInViewport, message);
}

async function assertSuggestionPlusButtonInline(suggestion, message) {
  const layout = await suggestion.evaluate((node) => {
    const button = node.querySelector("button[data-item-reuse]");
    const copy = node.querySelector(".item-suggestion-copy");
    const inertCheck = node.querySelector(".item-suggestion-check");
    if (!(button instanceof HTMLElement) || !(copy instanceof HTMLElement)) {
      return { hasButton: Boolean(button), hasCopy: Boolean(copy), hasInertCheck: Boolean(inertCheck) };
    }
    const buttonRect = button.getBoundingClientRect();
    const copyRect = copy.getBoundingClientRect();
    return {
      hasButton: true,
      hasCopy: true,
      hasInertCheck: Boolean(inertCheck),
      buttonBeforeCopy: buttonRect.right <= copyRect.left,
      verticallyOverlapsCopy: buttonRect.top < copyRect.bottom && buttonRect.bottom > copyRect.top,
    };
  });
  assert.deepEqual(
    layout,
    {
      hasButton: true,
      hasCopy: true,
      hasInertCheck: false,
      buttonBeforeCopy: true,
      verticallyOverlapsCopy: true,
    },
    message,
  );
}

async function assertBrownWhiteAccentChrome(page) {
  logStep("Checking brown-white accent chrome");
  const matches = await page.evaluate((tokens) => {
    const staleMatches = [];
    for (const sheet of [...document.styleSheets]) {
      let rules = [];
      try {
        rules = [...sheet.cssRules];
      } catch {
        continue;
      }

      for (const rule of rules) {
        const cssText = rule.cssText || "";
        const token = tokens.find((entry) => cssText.includes(entry));
        if (token) {
          staleMatches.push(`stylesheet:${token}:${cssText.slice(0, 160)}`);
        }
      }
    }

    const selectors = [
      ".item-category-header",
      ".item-card",
      ".checked-items-load-more",
      ".item-suggestion",
      ".item-more-fields",
      ".floating-add-button",
      ".list-toast",
      ".category-radio-card",
    ];
    const properties = [
      "backgroundColor",
      "backgroundImage",
      "borderTopColor",
      "borderRightColor",
      "borderBottomColor",
      "borderLeftColor",
      "boxShadow",
    ];

    for (const selector of selectors) {
      for (const node of [...document.querySelectorAll(selector)]) {
        const styles = getComputedStyle(node);
        for (const property of properties) {
          const value = styles[property];
          const token = tokens.find((entry) => value.includes(entry));
          if (token) {
            staleMatches.push(`${selector}:${property}:${value}`);
          }
        }
      }
    }

    return staleMatches;
  }, staleBlueAccentTokens);

  assert.deepEqual(matches, [], "Expected list chrome to avoid stale blue accent colors");
}

async function assertCategorySwatchColors(page, rowSelector, labelSelector, expectedColors) {
  const colors = await page.evaluate(
    ({ rowSelector, labelSelector }) => {
      const values = {};
      for (const row of [...document.querySelectorAll(rowSelector)]) {
        const label = row.querySelector(labelSelector)?.textContent?.trim();
        const swatch = row.querySelector(".item-category-swatch");
        if (label && swatch instanceof HTMLElement) {
          values[label] = getComputedStyle(swatch).backgroundColor;
        }
      }
      return values;
    },
    { rowSelector, labelSelector },
  );

  for (const [name, expectedColor] of expectedColors.entries()) {
    assert.equal(colors[name], expectedColor, `Expected ${name} swatch to keep its category color`);
  }
}

async function assertSeedMainCategoryColors(page) {
  logStep("Checking seeded category colors in main list");
  await assertCategorySwatchColors(
    page,
    ".item-category-group",
    ".item-category-header h3",
    seedMainCategoryColors,
  );
}

async function assertSeedSettingsCategoryColors(page) {
  logStep("Checking seeded category colors in list settings");
  await assertCategorySwatchColors(
    page,
    ".settings-category-row",
    ".settings-category-copy strong",
    seedSettingsCategoryColors,
  );
}

async function assertResponsiveHeaderActions(page) {
  logStep("Checking responsive header icons and compact menu");
  const originalViewport = page.viewportSize();
  await page.setViewportSize({ width: 780, height: 844 });
  await page.waitForFunction(() => {
    const settingsLink = document.querySelector('.app-header-actions .admin-link[href="/settings"]');
    return settingsLink && getComputedStyle(settingsLink).display !== "none";
  });

  const iconLayout = await page.evaluate(() => {
    const header = document.querySelector(".app-header");
    const settingsLink = document.querySelector('.app-header-actions .admin-link[href="/settings"]');
    const settingsIcon = settingsLink?.querySelector(".app-header-action-icon");
    const settingsLabel = settingsLink?.querySelector(".app-header-action-label");
    const menu = document.querySelector(".app-header-menu");
    return {
      headerFits: header instanceof HTMLElement && header.scrollWidth <= header.clientWidth,
      iconVisible: settingsIcon instanceof SVGElement && getComputedStyle(settingsIcon).display !== "none",
      labelWidth: settingsLabel instanceof HTMLElement ? settingsLabel.getBoundingClientRect().width : -1,
      menuHidden: menu instanceof HTMLElement && getComputedStyle(menu).display === "none",
    };
  });
  assert(iconLayout.headerFits, "Expected medium header to fit viewport");
  assert(iconLayout.iconVisible, "Expected medium header actions to use icons");
  assert(iconLayout.labelWidth <= 1, "Expected medium header action labels to be visually hidden");
  assert(iconLayout.menuHidden, "Expected compact menu to remain hidden at medium width");

  await page.setViewportSize({ width: 390, height: 844 });
  const menuToggle = page.locator(".app-header-menu summary");
  await expectVisible(menuToggle, "Expected compact header menu at narrow width");
  await menuToggle.click();
  await expectVisible(
    page.locator('.app-header-menu-list a[href="/settings"]'),
    "Expected settings link in compact header menu",
  );
  await expectVisible(
    page.locator(".app-header-menu-list .logout-button"),
    "Expected logout button in compact header menu",
  );
  const compactLayout = await page.evaluate(() => {
    const header = document.querySelector(".app-header");
    const actions = document.querySelector(".app-header-actions");
    const menu = document.querySelector(".app-header-menu-list");
    const menuRect = menu?.getBoundingClientRect();
    return {
      headerFits: header instanceof HTMLElement && header.scrollWidth <= header.clientWidth,
      actionsHidden: actions instanceof HTMLElement && getComputedStyle(actions).display === "none",
      menuFits:
        menuRect !== undefined &&
        menuRect.left >= 0 &&
        menuRect.right <= document.documentElement.clientWidth,
    };
  });
  assert(compactLayout.headerFits, "Expected narrow header to fit viewport");
  assert(compactLayout.actionsHidden, "Expected regular header actions hidden at narrow width");
  assert(compactLayout.menuFits, "Expected compact header menu to fit viewport");
  await menuToggle.click();
  if (originalViewport) {
    await page.setViewportSize(originalViewport);
  }
}

async function assertLoginPageTabs(page) {
  const signInTab = page.getByRole("tab", { name: "Use passkey" });
  const createAccountTab = page.getByRole("tab", { name: "Create account" });
  const signInButton = page.getByRole("button", { name: "Sign in with passkey" });
  await expectVisible(signInTab, "Expected the passkey mode switch on the login page");
  await expectVisible(createAccountTab, "Expected the create-account mode switch on the login page");
  await expectVisible(
    page.getByRole("heading", { name: "Sign In" }),
    "Expected the sign-in heading inside the active auth panel",
  );
  await expectInViewport(
    signInButton,
    "Expected the passkey sign-in button to be visible before scrolling on the login page",
  );
  const layout = await page.evaluate(() => {
    const shell = document.querySelector(".auth-shell");
    const copy = document.querySelector(".auth-copy");
    const panel = document.querySelector('[data-auth-tab-panel="signin"]');
    if (!(shell instanceof HTMLElement) || !(copy instanceof HTMLElement) || !(panel instanceof HTMLElement)) {
      throw new Error("Expected login shell, copy, and active panel");
    }
    const shellRect = shell.getBoundingClientRect();
    return {
      shellCenterOffset: Math.abs(shellRect.left + shellRect.width / 2 - window.innerWidth / 2),
      viewportWidth: window.innerWidth,
      copyTextAlign: getComputedStyle(copy).textAlign,
      panelTextAlign: getComputedStyle(panel).textAlign,
    };
  });
  assert(
    layout.shellCenterOffset <= Math.max(4, layout.viewportWidth * 0.02),
    "Expected the login widget to stay centered in the viewport",
  );
  assert.equal(layout.copyTextAlign, "left", "Expected login copy to be left aligned inside the centered widget");
  assert.equal(layout.panelTextAlign, "left", "Expected auth panel text to be left aligned inside the card");
}

async function assertFaviconAsset(page, requestContext) {
  logStep("Checking favicon link uses checked-in PNG asset");
  const favicon = page.locator('head link[rel="icon"]').first();
  await favicon.waitFor({ state: "attached" });
  assert.equal(await favicon.getAttribute("type"), "image/png");
  const href = await favicon.getAttribute("href");
  assert.equal(href, "/static/img/Favicon.png");

  const response = await requestContext.fetch(new URL(href, baseUrl).toString());
  assert(response.ok(), `Expected favicon asset to load, got ${response.status()}`);
  assert(
    response.headers()["content-type"]?.startsWith("image/png"),
    "Expected favicon asset to be served as image/png",
  );
}

async function assertLinkPreviewMetadata(page, requestContext) {
  logStep("Checking social link preview metadata uses PNG banner asset");
  const ogImage = page.locator('head meta[property="og:image"]').first();
  await ogImage.waitFor({ state: "attached" });
  const ogImageUrl = await ogImage.getAttribute("content");
  const expectedImageUrl = new URL("/static/img/link-preview.png", baseUrl).toString();
  assert.equal(ogImageUrl, expectedImageUrl);
  assert.equal(
    await page.locator('head meta[name="twitter:card"]').getAttribute("content"),
    "summary_large_image",
  );
  assert.equal(
    await page.locator('head meta[property="og:image:type"]').getAttribute("content"),
    "image/png",
  );
  assert.equal(
    await page.locator('head meta[property="og:image:width"]').getAttribute("content"),
    "1200",
  );
  assert.equal(
    await page.locator('head meta[property="og:image:height"]').getAttribute("content"),
    "630",
  );
  const response = await requestContext.fetch(ogImageUrl);
  assert(response.ok(), `Expected link preview image to load, got ${response.status()}`);
  assert(
    response.headers()["content-type"]?.startsWith("image/png"),
    "Expected link preview image to be served as image/png",
  );
}

async function assertSupportPage(page) {
  logStep("Checking public support page contact options");
  await page.goto(new URL("/support", baseUrl).toString(), { waitUntil: "networkidle" });
  await expectVisible(
    page.getByRole("heading", { name: "Need help with Planini?" }),
    "Expected public support page heading",
  );
  const headerSupportLink = page.locator('.app-header-actions a[href="/support"]');
  if (await headerSupportLink.isVisible()) {
    await expectVisible(headerSupportLink, "Expected support header link");
  } else {
    const menuToggle = page.locator(".app-header-menu summary");
    await expectVisible(menuToggle, "Expected compact header menu");
    await menuToggle.click();
    await expectVisible(
      page.locator('.app-header-menu-list a[href="/support"]'),
      "Expected support link in compact header menu",
    );
    await menuToggle.click();
  }

  const emailLink = page.locator(`a[href="mailto:${supportEmail}"]`);
  await expectVisible(emailLink, "Expected direct support email option");
  assert.equal(await emailLink.getAttribute("href"), `mailto:${supportEmail}`);

  const githubLink = page.locator('a[href="https://github.com/Malaber/planini/issues"]');
  await expectVisible(githubLink, "Expected GitHub issue option");
  assert.equal(await githubLink.getAttribute("target"), "_blank");
  assert.equal(await githubLink.getAttribute("rel"), "noopener noreferrer");
  await screenshot(page, "support-page");
}

async function assertPrivacyPage(page) {
  logStep("Checking public privacy page and configured contact");
  await page.goto(new URL("/privacy", baseUrl).toString(), { waitUntil: "networkidle" });
  await expectVisible(
    page.getByRole("heading", { name: "Privacy at Planini" }),
    "Expected public privacy page heading",
  );
  await expectVisible(
    page.getByRole("heading", { name: "No analytics or advertising" }),
    "Expected no-analytics privacy summary",
  );
  const contactLink = page.locator(`a[href="mailto:${privacyEmail}"]`);
  await expectVisible(contactLink, "Expected configured privacy contact");
  await expectVisible(
    page.locator('.app-footer a[href="/privacy"]'),
    "Expected privacy footer link",
  );
  await screenshot(page, "privacy-page");
}

async function screenshot(page, name) {
  await page.screenshot({ path: path.join(artifactDir, `${name}.png`), fullPage: true });
}

async function createVirtualAuthenticator(page) {
  const client = await page.context().newCDPSession(page);
  await client.send("WebAuthn.enable", { enableUI: false });
  const { authenticatorId } = await client.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      ctap2Version: "ctap2_1",
      transport: "usb",
      hasResidentKey: true,
      hasUserVerification: true,
      automaticPresenceSimulation: true,
      isUserVerified: true,
    },
  });
  await client.send("WebAuthn.setAutomaticPresenceSimulation", {
    authenticatorId,
    enabled: true,
  });
  await client.send("WebAuthn.setUserVerified", {
    authenticatorId,
    isUserVerified: true,
  });
  return { client, authenticatorId };
}

async function authenticatorCredentials(authenticator) {
  const { credentials } = await authenticator.client.send("WebAuthn.getCredentials", {
    authenticatorId: authenticator.authenticatorId,
  });
  return credentials;
}

async function removeCredential(authenticator, credentialId) {
  await authenticator.client.send("WebAuthn.removeCredential", {
    authenticatorId: authenticator.authenticatorId,
    credentialId,
  });
}

async function removeAuthenticator(authenticator) {
  await authenticator.client.send("WebAuthn.removeVirtualAuthenticator", {
    authenticatorId: authenticator.authenticatorId,
  });
}

async function installSeededPasskey(authenticator, user, rpId) {
  await authenticator.client.send("WebAuthn.addCredential", {
    authenticatorId: authenticator.authenticatorId,
    credential: {
      credentialId: toBase64(user.passkey.credential_id),
      isResidentCredential: true,
      rpId,
      privateKey: user.passkey.private_key_pkcs8_b64,
      userHandle: user.passkey.user_handle_b64,
      signCount: Number(user.passkey.sign_count ?? 0),
      userName: user.email,
      userDisplayName: user.display_name,
    },
  });
  const credentials = await authenticatorCredentials(authenticator);
  assert.equal(credentials.length, 1, `Expected seeded credential for ${user.email}`);
  return credentials[0];
}

async function passkeysFromSession(requestContext) {
  return apiJson(requestContext, "/api/v1/auth/passkeys");
}

async function visibleAppHeaderLink(page, href, label) {
  const regularLink = page.locator(`.app-header-actions a[href="${href}"]`);
  if (await regularLink.isVisible()) {
    return regularLink;
  }

  const menu = page.locator(".app-header-menu");
  const menuToggle = menu.locator("summary");
  await expectVisible(menuToggle, "Expected compact header menu");
  if ((await menu.getAttribute("open")) === null) {
    await menuToggle.click();
  }
  const compactLink = page.locator(`.app-header-menu-list a[href="${href}"]`);
  await expectVisible(compactLink, `Expected ${label} link in compact header menu`);
  return compactLink;
}

async function visibleAppHeaderLogout(page) {
  const regularButton = page.locator(".app-header-actions .logout-button");
  if (await regularButton.isVisible()) {
    return regularButton;
  }

  const menu = page.locator(".app-header-menu");
  const menuToggle = menu.locator("summary");
  await expectVisible(menuToggle, "Expected compact header menu");
  if ((await menu.getAttribute("open")) === null) {
    await menuToggle.click();
  }
  const compactButton = page.locator(".app-header-menu-list .logout-button");
  await expectVisible(compactButton, "Expected logout button in compact header menu");
  return compactButton;
}

function normalizeText(value) {
  return value.replace(/\s+/gu, " ").trim();
}

function assertTimestampIncludesOffset(value, label) {
  assert.equal(typeof value, "string", `${label} should be a timestamp string`);
  assert(
    /(?:Z|[+-]\d{2}:\d{2})$/.test(value),
    `${label} should include a UTC offset so browsers can convert it to local time; got ${value}`,
  );
}

function localizedBrowserDate(value, locale) {
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: browserTimeZone,
  }).format(new Date(value));
}

async function openSettingsPage(page) {
  await (await visibleAppHeaderLink(page, "/settings", "settings")).click();
  await page.waitForURL(/\/settings(\?|$)/);
}

async function runPasskeyManagementFlow(page, context, owner, rpId, authenticator) {
  logStep("Opening settings passkey management");
  await openSettingsPage(page);
  await expectVisible(
    page.getByRole("heading", { name: "Your passkeys" }),
    "Expected passkey management section",
  );

  const originalPasskeys = await passkeysFromSession(context.request);
  assert.equal(originalPasskeys.length, 1, "Expected one seeded passkey before adding another");
  const originalPasskeyName = originalPasskeys[0].name;
  await expectHidden(
    page.locator("[data-passkey-empty]"),
    "Expected passkey empty state to stay hidden when passkeys are rendered",
  );
  await expectVisible(
    page.locator(".passkey-row").first(),
    "Expected seeded passkey row in settings",
  );
  const originalPasskey = originalPasskeys[0];
  assertTimestampIncludesOffset(originalPasskey.created_at, "Passkey created_at");
  assertTimestampIncludesOffset(originalPasskey.last_used_at, "Passkey last_used_at");
  const locale = await page.evaluate(
    () => window.__appI18n?.locale || document.documentElement.lang || "en",
  );
  const expectedCreatedAt = localizedBrowserDate(originalPasskey.created_at, locale);
  const expectedLastUsedAt = localizedBrowserDate(originalPasskey.last_used_at, locale);
  const originalPasskeyRowText = normalizeText(await page.locator(".passkey-row").first().innerText());
  assert(
    originalPasskeyRowText.includes(normalizeText(expectedCreatedAt)),
    `Expected passkey created timestamp ${expectedCreatedAt} in local timezone; got ${originalPasskeyRowText}`,
  );
  assert(
    originalPasskeyRowText.includes(normalizeText(expectedLastUsedAt)),
    `Expected passkey last-used timestamp ${expectedLastUsedAt} in local timezone; got ${originalPasskeyRowText}`,
  );

  const seededCredential = (await authenticatorCredentials(authenticator))[0];
  assert(seededCredential, "Expected seeded credential in the virtual authenticator");
  await removeAuthenticator(authenticator);

  const secondAuthenticator = await createVirtualAuthenticator(page);

  logStep("Adding a second passkey through settings");
  const secondPasskeyName = "Laptop passkey";
  await page.getByRole("button", { name: "Add another passkey" }).click();
  await page.getByLabel("Name this passkey").fill(secondPasskeyName);
  await page.getByRole("button", { name: "Continue" }).click();
  await expectVisible(
    page.locator("[data-passkey-success]", { hasText: "Another passkey is ready to use." }),
    "Expected passkey add success message",
  );
  await expectVisible(
    page.locator(".passkey-row").nth(1),
    "Expected a second passkey row after enrollment",
  );

  const passkeysAfterAdd = await passkeysFromSession(context.request);
  assert.equal(passkeysAfterAdd.length, 2, "Expected backend to store the second passkey");
  assert.equal(passkeysAfterAdd[1].name, secondPasskeyName, "Expected backend to store the chosen passkey name");
  await expectVisible(
    page.locator(".passkey-row", { hasText: secondPasskeyName }),
    "Expected settings to show the chosen passkey name",
  );

  logStep("Renaming the new passkey after confirming it still works");
  const renamedPasskeyName = "Travel passkey";
  await page.locator(".passkey-row").nth(1).getByRole("button", { name: "Rename" }).click();
  await page.getByLabel("Rename this passkey").fill(renamedPasskeyName);
  await page.getByRole("button", { name: "Save and verify" }).click();
  await expectVisible(
    page.locator("[data-passkey-success]", {
      hasText: "Passkey renamed after confirming it still works.",
    }),
    "Expected passkey rename success message",
  );
  const passkeysAfterRename = await passkeysFromSession(context.request);
  assert.equal(passkeysAfterRename[1].name, renamedPasskeyName, "Expected backend to store the renamed passkey label");
  await expectVisible(
    page.locator(".passkey-row", { hasText: renamedPasskeyName }),
    "Expected settings to show the renamed passkey label",
  );

  const credentialsAfterAdd = await authenticatorCredentials(secondAuthenticator);
  assert.equal(
    credentialsAfterAdd.length,
    1,
    "Expected one credential on the second authenticator after enrollment",
  );
  const addedCredential = credentialsAfterAdd[0];
  assert(addedCredential, "Expected a newly enrolled passkey credential");

  const remainingAuthenticatorCredentials = await authenticatorCredentials(secondAuthenticator);
  assert.equal(
    remainingAuthenticatorCredentials.length,
    1,
    "Expected only the newly added passkey on the second authenticator",
  );
  assert.equal(
    remainingAuthenticatorCredentials[0].credentialId,
    addedCredential.credentialId,
    "Expected the second authenticator credential to be the newly added passkey",
  );

  logStep("Logging out and confirming the new passkey can log back in");
  await (await visibleAppHeaderLogout(page)).click();
  await page.waitForURL(/\/login(\?|$)/);
  await loginFromLoginPage(page, new URL("/", baseUrl).toString());
  await expectVisible(
    page.getByRole("heading", { name: "Households and Lists" }),
    "Expected login with the second passkey to succeed",
  );

  await openSettingsPage(page);
  logStep("Deleting the original passkey using the second passkey as confirmation");
  await page.locator(".passkey-row").nth(0).getByRole("button", { name: "Delete" }).click();
  const deletePanel = page.locator("[data-passkey-delete-panel]");
  await expectVisible(
    deletePanel.filter({
      hasText:
        `To delete ${originalPasskeyName}, you must authenticate with another passkey to confirm you still have a working Passkey after deleting one.`,
    }),
    "Expected passkey delete confirmation modal",
  );
  await expectVisible(
    deletePanel.locator("strong", { hasText: "another" }),
    "Expected the delete confirmation to emphasize another passkey",
  );
  await page.getByRole("button", { name: "Continue to verification" }).click();
  await expectVisible(
    page.locator("[data-passkey-success]", {
      hasText: "Passkey deleted after confirming another one worked.",
    }),
    "Expected passkey delete success message",
  );

  const passkeysAfterDelete = await passkeysFromSession(context.request);
  assert.equal(passkeysAfterDelete.length, 1, "Expected one passkey to remain after deletion");
  await page.waitForFunction(() => {
    const rows = [...document.querySelectorAll(".passkey-row")];
    if (rows.length !== 1) {
      return false;
    }
    const deleteButton = rows[0].querySelector("[data-passkey-delete]");
    return Boolean(deleteButton?.disabled);
  });

  await screenshot(page, "passkey-management");
  logStep("Passkey management checks passed");
}

async function loginFromLoginPage(page, expectedUrlPattern) {
  await assertLoginPageTabs(page);
  const signInButton = page.getByRole("button", { name: "Sign in with passkey" });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await signInButton.click();
    try {
      await page.waitForURL(expectedUrlPattern, {
        waitUntil: "commit",
        timeout: 10_000,
      });
      return;
    } catch (error) {
      if (attempt === 1 || !/\/login(\?|$)/.test(new URL(page.url()).pathname)) {
        throw error;
      }
    }
  }
}

async function loginFromRoot(page, user, expectedHeading) {
  await page.goto(new URL("/", baseUrl).toString(), { waitUntil: "networkidle" });
  await page.waitForURL(/\/login(\?|$)/);
  await screenshot(page, "redirect-login");
  await screenshot(page, "promotion-login-dialogue");
  await loginFromLoginPage(page, new URL("/", baseUrl).toString());
  await expectVisible(
    page.getByRole("heading", { name: expectedHeading }),
    `Expected heading ${expectedHeading}`,
  );
}

async function registerAccountFromLogin(page, { displayName, email }, expectedUrlPattern) {
  await page.goto(new URL("/", baseUrl).toString(), { waitUntil: "networkidle" });
  await page.waitForURL(/\/login(\?|$)/);
  await assertLoginPageTabs(page);
  await page.locator('[data-auth-tab-trigger="signup"]').click();
  await expectVisible(
    page.locator('[data-auth-tab-panel="signup"] h2'),
    "Expected the create account heading inside the active auth panel",
  );
  await page.locator('[data-passkey-register] input[name="display_name"]').fill(displayName);
  await page.locator('[data-passkey-register] input[name="email"]').fill(email);
  try {
    await Promise.all([
      page.waitForURL(expectedUrlPattern, { waitUntil: "commit", timeout: 10_000 }),
      page.locator('[data-passkey-register] input[name="email"]').press("Enter"),
    ]);
  } catch (error) {
    if (typeof expectedUrlPattern === "string" && page.url() === expectedUrlPattern) {
      return;
    }
    const dashboardHeading = page.getByRole("heading", { name: "Households and Lists" });
    if (await dashboardHeading.waitFor({ state: "visible", timeout: 5_000 }).then(() => true).catch(() => false)) {
      return;
    }
    const authError = await page.locator("[data-auth-error]").textContent().catch(() => "");
    if (authError.trim()) {
      throw new Error(`Passkey registration failed: ${authError.trim()}`);
    }
    throw error;
  }
}

async function loginAsAdmin(page, user) {
  await page.goto(new URL("/", baseUrl).toString(), { waitUntil: "networkidle" });
  await page.waitForURL(/\/login(\?|$)/);
  await loginFromLoginPage(page, /\/admin\/?$/);
  await expectVisible(page.getByText("Admin tools"), "Expected admin tools card after admin login");
}

async function runAdminTableControlsFlow(page) {
  logStep("Checking admin table sorting, page size persistence, and reset controls");
  await page.goto(new URL("/admin/user/list", baseUrl).toString(), { waitUntil: "networkidle" });
  await expectVisible(page.getByRole("link", { name: "50 / Page" }), "Expected 50 row default");

  await page.getByRole("link", { name: "50 / Page" }).click();
  await page.locator(".dropdown-menu .dropdown-item", { hasText: "100 / Page" }).click();
  await page.waitForURL(/\/admin\/user\/list\?pageSize=100/);

  await page.getByRole("link", { name: "Email" }).click();
  await page.waitForURL(/\/admin\/user\/list\?.*pageSize=100.*sortBy=email.*sort=asc/);

  await page.getByRole("link", { name: "Categories" }).click();
  await page.waitForURL(/\/admin\/category\/list\?pageSize=100/);
  await expectVisible(page.getByRole("link", { name: "100 / Page" }), "Expected page size to persist");

  await page.getByRole("link", { name: "Name" }).click();
  await page.waitForURL(/\/admin\/category\/list\?.*pageSize=100.*sortBy=name.*sort=asc/);

  await page.getByRole("link", { name: "Reset view" }).click();
  await page.waitForURL(new URL("/admin/category/list", baseUrl).toString());
  assert(!page.url().includes("?"), `Expected reset to clear admin table params, got ${page.url()}`);
}

async function runAdminBackupFlow(page) {
  logStep("Creating database backup from admin frontend");
  await page.locator('a.btn[href$="/admin/backups"]').click();
  await page.waitForURL(/\/admin\/backups$/);
  await expectVisible(
    page.getByRole("heading", { name: "Database backups" }),
    "Expected database backups admin page",
  );
  await page.getByRole("button", { name: "Create backup" }).click();
  const result = page.locator("[data-backup-result]");
  await expectVisible(result, "Expected admin backup success message");
  const fileName = (await page.locator("[data-backup-file-name]").innerText()).trim();
  assert.match(fileName, /^planini-sqlite-.+\.sql$/u);
  const stat = await fs.stat(path.join(backupDir, fileName));
  assert(stat.size > 0, `Expected backup file ${fileName} to be non-empty`);
  await screenshot(page, "admin-backup-created");
}

async function runAdminPasskeyAddLinkFlow(page, seed, rpId) {
  const adminUser = fixtureUser(seed, "planini_admin@schaedler.rocks");
  const targetUser = fixtureAccount(seed, "review-neighbor@example.com");

  logStep("Checking that a normal user cannot access admin user management");
  await page.goto(new URL("/admin/user/list", baseUrl).toString(), { waitUntil: "networkidle" });
  await page.waitForURL(new URL("/", baseUrl).toString());
  await expectHidden(
    page.getByRole("link", { name: "Admin" }),
    "Expected no admin link for a normal signed-in user",
  );

  const adminContext = await page.context().browser().newContext({
    viewport: { width: 1440, height: 1200 },
    locale: browserLocale,
    timezoneId: browserTimeZone,
  });
  const adminPage = await adminContext.newPage();
  const recipientContext = await page.context().browser().newContext({
    viewport: { width: 1440, height: 1200 },
    locale: browserLocale,
    timezoneId: browserTimeZone,
  });
  const replayContext = await page.context().browser().newContext({
    viewport: { width: 1440, height: 1200 },
    locale: browserLocale,
    timezoneId: browserTimeZone,
  });

  try {
    const adminAuthenticator = await createVirtualAuthenticator(adminPage);
    await installSeededPasskey(adminAuthenticator, adminUser, rpId);

    logStep("Signing in as admin and generating an add-passkey link from the user edit page");
    await loginAsAdmin(adminPage, adminUser);
    await runAdminBackupFlow(adminPage);
    await runAdminTableControlsFlow(adminPage);
    await adminPage.goto(new URL("/admin/user/list", baseUrl).toString(), { waitUntil: "networkidle" });
    const targetUserRow = adminPage.locator("tr", { hasText: targetUser.email }).first();
    await expectVisible(
      targetUserRow,
      `Expected to find an admin user row for ${targetUser.email}`,
    );
    await targetUserRow.locator('a[href*="/admin/user/edit/"]').first().click();
    await adminPage.waitForURL(/\/admin\/user\/edit\/.+$/);
    await expectVisible(
      adminPage.getByRole("button", { name: "Generate add-passkey link" }),
      "Expected add-passkey link generator on the admin user edit page",
    );
    await expectVisible(
      adminPage.getByRole("heading", { name: "Valid links" }),
      "Expected valid passkey add links section on the admin user edit page",
    );
    await adminPage.getByLabel("Valid for hours").fill("48");
    await adminPage.getByRole("button", { name: "Generate add-passkey link" }).click();
    await expectVisible(
      adminPage.locator("#passkey-add-link"),
      "Expected generated admin link input after creating an add-passkey link",
    );
    await expectVisible(
      adminPage.locator("text=Valid for 48 hours."),
      "Expected generated admin link to show the configured duration",
    );
    await expectVisible(
      adminPage.getByRole("columnheader", { name: "Valid until" }),
      "Expected generated admin link to show its valid-until column",
    );
    const generatedLink = await adminPage.locator("#passkey-add-link").inputValue();
    assert(
      generatedLink.includes("/passkey-add/") && generatedLink.includes("#identifier="),
      `Expected generated admin link to use /passkey-add/token#identifier=..., got ${generatedLink}`,
    );

    logStep("Updating the generated add-passkey link duration from the valid links table");
    await adminPage.locator("[data-passkey-link-duration]").first().fill("72");
    await adminPage.getByRole("button", { name: "Update duration" }).first().click();
    await adminPage.waitForURL(/passkey_add_notice=/);
    await expectVisible(
      adminPage.locator("text=duration updated to 72 hours."),
      "Expected generated admin link duration update confirmation",
    );

    const recipientPage = await recipientContext.newPage();
    const recipientAuthenticator = await createVirtualAuthenticator(recipientPage);

    try {
      logStep("Following the generated add-passkey link and registering a passkey");
      await recipientPage.goto(generatedLink, { waitUntil: "networkidle" });
      await expectVisible(
        recipientPage.getByRole("heading", { name: "Add passkey" }),
        "Expected the add-passkey landing page from the generated admin link",
      );
      await recipientPage.getByRole("button", { name: "Create additional passkey" }).click();
      await recipientPage.waitForURL(new URL("/", baseUrl).toString(), { waitUntil: "commit" });
      await expectVisible(
        recipientPage.getByRole("heading", { name: "Households and Lists" }),
        "Expected the generated-link user to land in the normal app after enrollment",
      );
    } finally {
      await removeAuthenticator(recipientAuthenticator);
      await recipientPage.close();
    }

    logStep("Ensuring the generated add-passkey link is single-use");
    const replayPage = await replayContext.newPage();
    try {
      await replayPage.goto(generatedLink, { waitUntil: "networkidle" });
      await replayPage.waitForURL(/\/login([?#]|$)/);
    } finally {
      await replayPage.close();
    }

    await screenshot(adminPage, "admin-user-passkey-link");
  } finally {
    await adminPage.close();
    await replayContext.close();
    await recipientContext.close();
    await adminContext.close();
  }
}

async function scenarioFromSeed(seed, requestContext) {
  const households = await apiJson(requestContext, "/api/v1/households");
  const household = households.find((entry) => entry.name === seed.e2e.primary_household);
  assert(household, `Expected household ${seed.e2e.primary_household} from seeded fixture`);
  const lists = await apiJson(requestContext, `/api/v1/households/${household.id}/lists`);
  const groceryList = lists.find((entry) => entry.name === seed.e2e.primary_list);
  assert(groceryList, `Expected seeded list ${seed.e2e.primary_list}`);
  const checkedStressList = lists.find((entry) => entry.name === seed.e2e.checked_stress_list);
  assert(checkedStressList, `Expected seeded list ${seed.e2e.checked_stress_list}`);
  const alternateList = lists.find(
    (entry) => entry.id !== groceryList.id && entry.id !== checkedStressList.id,
  );
  assert(alternateList, "Expected another seeded list for quick switching and item move coverage");
  return {
    checkedStressListId: checkedStressList.id,
    householdId: household.id,
    householdName: household.name,
    listId: groceryList.id,
    listName: groceryList.name,
    moveTargetListId: alternateList.id,
    moveTargetListName: alternateList.name,
    quickSwitchListId: alternateList.id,
    quickSwitchListName: alternateList.name,
  };
}

async function openItemCountLabel(requestContext, listId) {
  const items = await apiJson(requestContext, `/api/v1/lists/${listId}/items`);
  const openItemCount = items.filter((item) => !item.checked).length;
  return openItemCount === 1 ? "1 open item" : `${openItemCount} open items`;
}

async function resetFixtureItems(requestContext, listId, expectedChecked = new Map()) {
  const items = await apiJson(requestContext, `/api/v1/lists/${listId}/items`);
  for (const item of items) {
    if (item.name.startsWith("Fresh thing") || item.name.startsWith("Move target")) {
      await apiJson(requestContext, `/api/v1/items/${item.id}`, { method: "DELETE" });
      continue;
    }

    if (!expectedChecked.has(item.name)) {
      continue;
    }

    if (item.hidden_until) {
      await apiJson(requestContext, `/api/v1/items/${item.id}`, {
        method: "PATCH",
        data: { hidden_until: null },
      });
    }

    const shouldBeChecked = expectedChecked.get(item.name);
    if (Boolean(item.checked) === shouldBeChecked) {
      continue;
    }

    await apiJson(requestContext, `/api/v1/items/${item.id}/${shouldBeChecked ? "check" : "uncheck"}`, {
      method: "POST",
    });
  }
}

async function textList(locator) {
  return locator.evaluateAll((nodes) => nodes.map((node) => node.textContent?.trim() || ""));
}

function itemCard(page, text) {
  return page.locator(".item-card", { hasText: text }).first();
}

async function swipeItemRight(card) {
  await card.evaluate((node) => {
    const rect = node.getBoundingClientRect();
    const startX = rect.left + Math.min(24, rect.width * 0.18);
    const endX = Math.min(rect.right - 12, startX + 120);
    const y = rect.top + rect.height / 2;
    const base = {
      bubbles: true,
      cancelable: true,
      pointerId: 42,
      pointerType: "touch",
      isPrimary: true,
    };
    node.dispatchEvent(new PointerEvent("pointerdown", {
      ...base,
      buttons: 1,
      clientX: startX,
      clientY: y,
    }));
    node.dispatchEvent(new PointerEvent("pointermove", {
      ...base,
      buttons: 1,
      clientX: endX,
      clientY: y,
    }));
    node.dispatchEvent(new PointerEvent("pointerup", {
      ...base,
      buttons: 0,
      clientX: endX,
      clientY: y,
    }));
  });
}

async function dragCategoryAfter(page, sourceName, targetName) {
  await page.evaluate(
    ({ sourceName, targetName }) => {
      const rowByName = (name) =>
        [...document.querySelectorAll(".settings-category-row")].find((row) =>
          row.textContent?.includes(name),
        );
      const sourceRow = rowByName(sourceName);
      const targetRow = rowByName(targetName);
      const handle = sourceRow?.querySelector("[data-settings-category-grabber]");
      const root = handle?.closest("[data-list-detail]");
      if (!(handle instanceof HTMLElement) || !(targetRow instanceof HTMLElement) || !(root instanceof HTMLElement)) {
        throw new Error(`Could not find category drag rows ${sourceName} and ${targetName}`);
      }

      const handleRect = handle.getBoundingClientRect();
      const targetRect = targetRow.getBoundingClientRect();
      const x = targetRect.left + targetRect.width / 2;
      const y = targetRect.top + targetRect.height * 0.75;
      const pointerId = 77;
      const base = {
        bubbles: true,
        cancelable: true,
        pointerId,
        pointerType: "touch",
        isPrimary: true,
      };
      handle.dispatchEvent(new PointerEvent("pointerdown", {
        ...base,
        buttons: 1,
        clientX: handleRect.left + handleRect.width / 2,
        clientY: handleRect.top + handleRect.height / 2,
      }));
      root.dispatchEvent(new PointerEvent("pointermove", {
        ...base,
        buttons: 1,
        clientX: x,
        clientY: y,
      }));
      window.__planiniFinishCategoryDrag = () => {
        root.dispatchEvent(new PointerEvent("pointerup", {
          ...base,
          buttons: 0,
          clientX: x,
          clientY: y,
        }));
        delete window.__planiniFinishCategoryDrag;
      };
    },
    { sourceName, targetName },
  );

  await expectVisible(
    page.locator(".settings-category-row.is-drop-after"),
    "Expected category reorder to mark the insertion gap",
  );
  await page.evaluate(() => window.__planiniFinishCategoryDrag?.());
  await page.waitForFunction(
    ({ sourceName, targetName }) => {
      const labels = [...document.querySelectorAll(".settings-category-row strong")].map(
        (node) => node.textContent?.trim(),
      );
      return labels.indexOf(sourceName) > labels.indexOf(targetName);
    },
    { sourceName, targetName },
    { timeout: 5000 },
  );
  await page.waitForFunction(
    () => !document.querySelector("[data-category-order-status]:not([hidden])"),
    null,
    { timeout: 5000 },
  );
}

async function revealCheckedItemCard(page, text) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const card = itemCard(page, text);
    if (await card.isVisible()) {
      return card;
    }

    const loadMoreButton = page.locator(".checked-items-load-more button").first();
    if (!(await loadMoreButton.isVisible())) {
      break;
    }
    await loadMoreButton.click();
  }

  throw new Error(`Could not reveal checked item card for ${text}`);
}

async function expectCheckedCardCount(group, count) {
  await group.locator(".item-card").nth(count - 1).waitFor({ state: "visible" });
  assert.equal(await group.locator(".item-card").count(), count);
}

async function runCheckedStressListFlow(page, stressListUrl) {
  logStep("Checking large checked-off list pagination");
  await page.goto(stressListUrl, { waitUntil: "networkidle" });

  const checkedGroup = page
    .locator(".item-category-group")
    .filter({ has: page.locator(".item-category-header h3", { hasText: "Checked off" }) })
    .first();
  const headingMeta = checkedGroup.locator(".item-category-header .item-category-meta");
  const loadMoreButton = checkedGroup.locator(".checked-items-load-more button");
  const loadMoreMeta = checkedGroup.locator(".checked-items-load-more .item-category-meta");

  await expectVisible(checkedGroup, "Expected checked-off group on large checked list");
  await expectCheckedCardCount(checkedGroup, 10);
  assert.equal(await headingMeta.textContent(), "258 items");
  assert.equal(await loadMoreButton.textContent(), "Load 100 more");
  assert.equal(await loadMoreMeta.textContent(), "248 older items not loaded");
  await assertBrownWhiteAccentChrome(page);

  await loadMoreButton.click();
  await expectCheckedCardCount(checkedGroup, 110);
  assert.equal(await headingMeta.textContent(), "258 items");
  assert.equal(await loadMoreButton.textContent(), "Load 100 more");
  assert.equal(await loadMoreMeta.textContent(), "148 older items not loaded");

  await loadMoreButton.click();
  await expectCheckedCardCount(checkedGroup, 210);
  assert.equal(await headingMeta.textContent(), "258 items");
  assert.equal(await loadMoreButton.textContent(), "Load 48 more");
  assert.equal(await loadMoreMeta.textContent(), "48 older items not loaded");

  await loadMoreButton.click();
  await expectCheckedCardCount(checkedGroup, 258);
  assert.equal(await headingMeta.textContent(), "258 items");
  assert.equal(await checkedGroup.locator(".checked-items-load-more").count(), 0);
}

async function runListQuickSwitchFlow(page, scenario, primaryListUrl) {
  logStep("Checking list quick switch control");
  const switcher = page.locator("[data-list-switcher]");
  await expectVisible(switcher, "Expected quick switch control when household has multiple lists");
  await expectVisible(page.getByRole("link", { name: "All lists" }), "Expected clear dashboard link label");

  const headerLayout = await page.evaluate(() => {
    const kicker = document.querySelector(".list-kicker-row .dashboard-kicker");
    const actions = document.querySelector(".list-kicker-row .list-hero-actions");
    const titleRow = document.querySelector(".list-title-row");
    const focusCard = document.querySelector(".list-focus-card");
    if (
      !(kicker instanceof HTMLElement) ||
      !(actions instanceof HTMLElement) ||
      !(titleRow instanceof HTMLElement) ||
      !(focusCard instanceof HTMLElement)
    ) {
      throw new Error("Expected list kicker, header actions, title row, and focus card");
    }

    const kickerRect = kicker.getBoundingClientRect();
    const actionsRect = actions.getBoundingClientRect();
    const titleRect = titleRow.getBoundingClientRect();
    const focusRect = focusCard.getBoundingClientRect();
    return {
      actionCenterOffset: Math.abs(
        actionsRect.top + actionsRect.height / 2 - (kickerRect.top + kickerRect.height / 2),
      ),
      actionsBottom: actionsRect.bottom,
      focusTop: focusRect.top,
      titleBottom: titleRect.bottom,
      titleTop: titleRect.top,
    };
  });
  assert(
    headerLayout.actionCenterOffset <= 22,
    "Expected list settings and all-lists controls to stay inline with the shopping-list kicker",
  );
  assert(
    headerLayout.actionsBottom <= headerLayout.titleTop,
    "Expected list header controls to sit above the title switcher, not below the hero gap",
  );
  assert(
    headerLayout.focusTop - headerLayout.titleBottom <= 80,
    "Expected list content to sit directly below the title switcher without a mobile hero spacer",
  );

  const select = switcher.locator("[data-list-switcher-select]");
  assert.equal(await select.inputValue(), scenario.listId);
  await select.selectOption(scenario.quickSwitchListId);
  await page.waitForURL(new URL(`/lists/${scenario.quickSwitchListId}`, baseUrl).toString());
  await expectVisible(
    page.locator("[data-list-title]", { hasText: scenario.quickSwitchListName }),
    "Expected quick switch target list to load",
  );

  await page.locator("[data-list-switcher-select]").selectOption(scenario.listId);
  await page.waitForURL(primaryListUrl);
  await expectVisible(
    page.locator("[data-list-title]", { hasText: scenario.listName }),
    "Expected quick switch to return to the primary list",
  );
}

async function runOfflineSyncFlow(page, requestContext, listId) {
  logStep("Checking offline list item save and resync");
  const offlineName = `Fresh thing offline ${Date.now()}`;
  const addForm = page.locator("[data-item-form]");

  await page.context().setOffline(true);
  try {
    await page.getByRole("button", { name: "Add item" }).click();
    await addForm.getByLabel("Item name").fill(offlineName);
    await page.locator(".add-item-save-button").click();
    await expectVisible(
      page.locator("[data-list-error]", { hasText: "Offline. Changes saved locally" }),
      "Offline add should show local-only error",
    );
    const offlineCard = itemCard(page, offlineName);
    await expectVisible(offlineCard, "Offline-created item should render immediately");
    await offlineCard.getByRole("button").first().click();
    await expectVisible(
      page.locator("[data-list-error]", { hasText: "Offline. Changes saved locally" }),
      "Offline check should keep local-only error",
    );
  } finally {
    await page.context().setOffline(false);
  }

  await page.evaluate(() => window.dispatchEvent(new Event("online")));
  await expectVisible(
    page.locator("[data-list-success]", { hasText: "Saved offline changes synced." }),
    "Offline changes should sync after reconnect",
  );
  const items = await apiJson(requestContext, `/api/v1/lists/${listId}/items`);
  const syncedItem = items.find((item) => item.name === offlineName);
  assert(syncedItem, "Expected offline-created item to exist after sync");
  assert.equal(syncedItem.checked, true, "Expected offline checked state to sync");
}

function extractInviteToken(inviteUrl) {
  const invitePath = new URL(inviteUrl).pathname;
  return invitePath.split("/").filter(Boolean).at(-1);
}

async function runInviteFlow(ownerPage, browser, scenario, seed, rpId) {
  logStep("Creating and accepting a household invite");
  const expectedOpenItemLabel = await openItemCountLabel(
    ownerPage.context().request,
    scenario.listId,
  );
  await ownerPage.goto(new URL("/?dashboard=1", baseUrl).toString(), { waitUntil: "networkidle" });
  await expectVisible(
    ownerPage.getByRole("heading", { name: "Households and Lists" }),
    "Expected dashboard heading",
  );

  const ownerHouseholdCard = ownerPage
    .locator(".household-card", { hasText: scenario.householdName })
    .first();
  await expectVisible(ownerHouseholdCard, "Expected seeded household card on dashboard");
  const ownerListLink = ownerHouseholdCard.locator(`a[href="/lists/${scenario.listId}"]`);
  await expectVisible(
    ownerListLink.filter({ hasText: expectedOpenItemLabel }),
    "Expected dashboard list link to show open item count",
  );

  await ownerHouseholdCard.getByRole("button", { name: "Create invite link" }).click();
  const invitePanel = ownerPage.locator("[data-dashboard-invite-panel]");
  await expectVisible(invitePanel, "Expected invite share sheet");
  await invitePanel.getByLabel("Limit").selectOption("uses");
  await invitePanel.locator("[data-invite-max-uses]").fill("2");
  await invitePanel.getByRole("button", { name: "Create invite link" }).click();
  const inviteInput = invitePanel.locator("[data-invite-sheet-link-input]");
  await expectVisible(inviteInput, "Expected invite link field after creating invite");
  const inviteUrl = await inviteInput.inputValue();
  assert(inviteUrl.includes("/invite/"), "Expected invite URL");
  const inviteToken = extractInviteToken(inviteUrl);
  assert(inviteToken, "Expected invite token");
  const invitePreview = await apiJson(
    ownerPage.context().request,
    `/api/v1/households/invites/${inviteToken}`,
  );
  assert.equal(invitePreview.max_uses, 2, "Expected limited-use invite");
  assert.equal(invitePreview.remaining_uses, 2, "Expected unused invite to show both uses");

  const inviteeContext = await browser.newContext(contextOptions());
  const inviteePage = await inviteeContext.newPage();
  const invitee = fixtureUser(seed, seed.e2e.invitee_email);

  try {
    const inviteeAuthenticator = await createVirtualAuthenticator(inviteePage);
    await installSeededPasskey(inviteeAuthenticator, invitee, rpId);
    await inviteePage.goto(new URL("/", baseUrl).toString(), { waitUntil: "networkidle" });
    await inviteePage.waitForURL(/\/login(\?|$)/);
    await loginFromLoginPage(inviteePage, new URL("/", baseUrl).toString());
    await expectVisible(
      inviteePage.getByRole("heading", { name: "Households and Lists" }),
      "Invitee should reach the dashboard before accepting an invite",
    );
    assert.equal(
      await inviteePage.locator(".household-card", { hasText: scenario.householdName }).count(),
      0,
      "Invitee should not see the owner's household before accepting an invite",
    );

    await inviteeContext.request.post(new URL("/api/v1/auth/logout", baseUrl).toString());
    await inviteePage.goto(inviteUrl, { waitUntil: "networkidle" });
    await inviteePage.waitForURL(/\/login\?next=%2Finvite%2F|\/login\?next=\/invite\//);
    await screenshot(inviteePage, "invite-redirect-login");

    await loginFromLoginPage(inviteePage, /\/invite\//);
    await expectVisible(
      inviteePage.getByRole("heading", { name: "Join a shared grocery space" }),
      "Expected invite details page after passkey login",
    );
    await expectVisible(
      inviteePage.getByRole("heading", { name: scenario.householdName }),
      "Expected invite page household name",
    );
    await expectVisible(
      inviteePage.getByText("This link has 2 uses remaining."),
      "Expected limited-use invite copy",
    );
    await inviteePage.getByRole("button", { name: "Accept invite" }).click();
    await inviteePage.waitForURL(new URL("/", baseUrl).toString());
    const acceptedHouseholdCard = inviteePage
      .locator(".household-card", { hasText: scenario.householdName })
      .filter({ hasText: scenario.listName })
      .first();
    await expectVisible(
      acceptedHouseholdCard,
      "Invitee should see the seeded list after accepting the invite",
    );
    await expectVisible(
      acceptedHouseholdCard
        .locator(`a[href="/lists/${scenario.listId}"]`)
        .filter({ hasText: expectedOpenItemLabel }),
      "Invitee should see the seeded list open item count after accepting the invite",
    );
    await screenshot(inviteePage, "invite-accepted");
  } finally {
    await inviteeContext.close();
  }
}

async function runDashboardEmptyStateFlow(browser) {
  logStep("Checking dashboard empty-state add cards");
  const context = await browser.newContext(contextOptions());
  const page = await context.newPage();
  const authenticator = await createVirtualAuthenticator(page);
  const timestamp = Date.now();
  const emptyStateAccount = {
    displayName: `Dashboard Empty ${timestamp}`,
    email: `dashboard-empty-${timestamp}@example.com`,
  };

  try {
    await registerAccountFromLogin(page, emptyStateAccount, new URL("/", baseUrl).toString());
    await expectVisible(
      page.getByRole("heading", { name: "Households and Lists" }),
      "Expected a brand-new account to land on the dashboard",
    );

    const ordering = await page.evaluate(() => {
      const lists = document.querySelector(".dashboard-lists");
      const organized = document.querySelector("[data-dashboard-organized]");
      if (!(lists instanceof HTMLElement) || !(organized instanceof HTMLElement)) {
        return null;
      }
      return lists.compareDocumentPosition(organized);
    });
    assert(ordering !== null, "Expected dashboard lists section and organized section");
    assert(
      Boolean(ordering & 4),
      "Expected the organized section to appear after the lists section",
    );

    const emptyHouseholdButton = page.locator(
      '[data-dashboard-empty] [data-dashboard-add-option="household"]',
    );
    await expectVisible(emptyHouseholdButton, "Expected add-household action card when no households exist");
    await emptyHouseholdButton.click();
    await expectVisible(
      page.getByRole("heading", { name: "Add household" }),
      "Expected add-household panel from the empty-state card",
    );

    const householdName = "Fresh household";
    await page.getByLabel("Household name").fill(householdName);
    await page.getByRole("button", { name: "Create household" }).click();
    const newHouseholdCard = page.locator(".household-card", { hasText: householdName }).first();
    await expectVisible(newHouseholdCard, "Expected the new household to appear on the dashboard");

    const emptyListButton = newHouseholdCard.locator('[data-dashboard-add-option="list"]');
    await expectVisible(emptyListButton, "Expected add-list action card for a household without lists");
    await emptyListButton.click();
    await expectVisible(
      page.getByRole("heading", { name: "Add list to household" }),
      "Expected add-list panel from the empty-state card",
    );

    const listName = "Fresh list";
    await page.getByLabel("List name").fill(listName);
    await page.getByRole("button", { name: "Create list" }).click();
    await page.waitForURL(/\/lists\/.+$/);
    await expectVisible(
      page.getByRole("heading", { name: listName }),
      "Expected the new list detail page after creating a list from the empty-state card",
    );
    await screenshot(page, "dashboard-empty-state-actions");
  } finally {
    await removeAuthenticator(authenticator);
    await context.close();
  }
}

async function main() {
  logStep(`Preparing artifacts in ${artifactDir}`);
  await resetDir(artifactDir);
  await ensureDir(videoDir);

  logStep(`Loading seed fixture from ${seedPath}`);
  const seed = await loadSeed();
  const rpId = process.env.WEBAUTHN_RP_ID ?? seed.e2e.rp_id ?? new URL(baseUrl).hostname;
  const owner = fixtureUser(seed, seed.e2e.owner_email);
  const seededPrimaryList = fixturePrimaryList(seed);
  const expectedChecked = new Map(
    seededPrimaryList.items.map((item) => [item.name, Boolean(item.checked)]),
  );

  let browser;
  let page;

  try {
    logStep(`Launching browser flow against ${baseUrl}`);
    browser = await chromium.launch(browserChannel ? { channel: browserChannel } : {});
    const context = await browser.newContext(contextOptions());
    page = await context.newPage();
    const authenticator = await createVirtualAuthenticator(page);
    await installSeededPasskey(authenticator, owner, rpId);
    await assertSupportPage(page);
    await assertPrivacyPage(page);
    logStep("Signing in with the seeded owner passkey");
    await loginFromRoot(page, owner, "Households and Lists");
    await screenshot(page, "promotion-list-of-lists");
    await assertFaviconAsset(page, context.request);
    await assertLinkPreviewMetadata(page, context.request);
    await assertResponsiveHeaderActions(page);
    await runAdminPasskeyAddLinkFlow(page, seed, rpId);
    await runPasskeyManagementFlow(page, context, owner, rpId, authenticator);
    await runDashboardEmptyStateFlow(browser);

    const scenario = await scenarioFromSeed(seed, context.request);
    logStep(`Resetting seeded list state for ${scenario.listName}`);
    await resetFixtureItems(context.request, scenario.listId, expectedChecked);
    await resetFixtureItems(context.request, scenario.moveTargetListId);
    const listUrl = new URL(`/lists/${scenario.listId}`, baseUrl).toString();
    const checkedStressListUrl = new URL(`/lists/${scenario.checkedStressListId}`, baseUrl).toString();

    if (owner.is_admin) {
      await visibleAppHeaderLink(page, "/admin", "admin");

      const adminPage = await context.newPage();
      await adminPage.goto(new URL("/admin", baseUrl).toString(), { waitUntil: "networkidle" });
      await expectVisible(
        adminPage.getByRole("link", { name: "Go to application" }),
        "Expected Go to application link in admin",
      );
      await screenshot(adminPage, "admin-home");
      await adminPage.close();
    }

    const pageTwo = await context.newPage();
    await Promise.all([
      page.goto(listUrl, { waitUntil: "networkidle" }),
      pageTwo.goto(listUrl, { waitUntil: "networkidle" }),
    ]);

    const addForm = page.locator("[data-item-form]");
    const editForm = page.locator("[data-item-edit-form]");

    logStep("Running main list interaction flow");
    await expectVisible(page.getByRole("button", { name: "Add item" }), "Expected floating add button");
    await expectVisible(page.locator(".item-card", { hasText: "Spaghetti" }), "Expected seeded items to load");
    await assertSeedMainCategoryColors(page);
    await assertBrownWhiteAccentChrome(page);
    await runListQuickSwitchFlow(page, scenario, listUrl);

    if (deviceName === "desktop") {
      await page.keyboard.press("Enter");
      await expectVisible(page.locator("[data-item-panel]"), "Enter should open add modal");
    } else {
      await page.getByRole("button", { name: "Add item" }).click();
      await expectVisible(page.locator("[data-item-panel]"), "Add button should open add modal");
    }
    await addForm.getByLabel("Item name").fill("Spaghetty");
    const activeSuggestion = addForm.locator(".item-suggestion", { hasText: "Spaghetti" });
    await expectVisible(activeSuggestion, "Expected fuzzy duplicate suggestion for active item");
    await assertSuggestionPlusButtonInline(activeSuggestion, "Suggestion plus should replace checkbox circle inline");
    await activeSuggestion.locator("button").click();
    await expectHidden(page.locator("[data-item-panel]"), "Suggestion reuse should close add modal");
    await page.waitForSelector('[data-item-card].is-highlighted', { timeout: 3000 });

    const spaghettiCard = itemCard(page, "Spaghetti");
    if (deviceName === "desktop") {
      const cardCountBeforeMenu = await page.locator(".item-card").count();
      const cardHeightBeforeMenu = (await spaghettiCard.boundingBox())?.height ?? 0;
      await spaghettiCard.getByRole("button", { name: "More actions for Spaghetti" }).click();
      await expectVisible(
        spaghettiCard.getByRole("button", { name: "Hide item for 4h" }),
        "Expected more-actions context menu",
      );
      assert.equal(
        await page.locator(".item-card").count(),
        cardCountBeforeMenu,
        "Opening item actions should not add a list row",
      );
      const cardHeightAfterMenu = (await spaghettiCard.boundingBox())?.height ?? 0;
      assert(
        Math.abs(cardHeightAfterMenu - cardHeightBeforeMenu) <= 2,
        `Opening item actions should not resize the item row; before ${cardHeightBeforeMenu}, after ${cardHeightAfterMenu}`,
      );
      await spaghettiCard.getByRole("button", { name: "Hide item for 4h" }).click();
    } else {
      await swipeItemRight(spaghettiCard);
    }
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: "Spaghetti hidden for 4 hours." }),
      "Expected hide-for-later toast",
    );
    const hiddenGroup = page.locator(".item-hidden-group");
    const hiddenSpaghetti = hiddenGroup.locator(".item-card", { hasText: "Spaghetti" });
    await expectVisible(hiddenSpaghetti, "Hidden item should move into the hidden section");
    await expectVisible(
      hiddenSpaghetti.getByRole("button", { name: "Show Spaghetti now" }),
      "Hidden item should expose a time button for unhiding",
    );
    await pageTwo.waitForFunction(
      () => {
        const hiddenGroup = document.querySelector(".item-hidden-group");
        return Boolean(hiddenGroup?.textContent?.includes("Spaghetti"));
      },
      { timeout: 5000 },
    );
    await hiddenSpaghetti.getByRole("button", { name: "Show Spaghetti now" }).click();
    await expectHidden(hiddenGroup.locator(".item-card", { hasText: "Spaghetti" }), "Time button should unhide item");
    await expectVisible(itemCard(page, "Spaghetti"), "Unhidden item should return to normal categories");
    await pageTwo.waitForFunction(
      () => {
        const hiddenGroup = document.querySelector(".item-hidden-group");
        if (hiddenGroup?.textContent?.includes("Spaghetti")) {
          return false;
        }
        return [...document.querySelectorAll(".item-card")].some((node) =>
          node.textContent?.includes("Spaghetti"),
        );
      },
      { timeout: 5000 },
    );

    await page.getByRole("button", { name: "Add item" }).click();
    await addForm.getByLabel("Item name").fill("Broz");
    const checkedSuggestion = addForm.locator(".item-suggestion", { hasText: "Brot" });
    await expectVisible(checkedSuggestion, "Expected fuzzy suggestion for checked duplicate item");
    await assertSuggestionPlusButtonInline(checkedSuggestion, "Checked suggestion plus should replace checkbox circle inline");
    await checkedSuggestion.locator("button").click();
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: "Brot added back to the list." }),
      "Expected re-add toast",
    );
    await page.locator(".item-category-header h3", { hasText: "Checked off" }).waitFor({ state: "hidden" });
    await expectVisible(page.locator(".item-card", { hasText: "Brot" }), "Brot should be active again");

    const backwarenHeader = page.locator(".item-category-header h3", { hasText: "Backwaren" }).first();
    await expectVisible(backwarenHeader, "Expected Backwaren section");

    const looseItemCard = page.locator(".item-card", { hasText: "Loose item" });
    await looseItemCard.getByRole("button").first().click();
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: "Loose item checked." }),
      "Expected check toast",
    );
    await page.locator("[data-list-toast-undo]").click();
    await expectVisible(
      page.locator(".item-card", { hasText: "Loose item" }),
      "Undo should restore unchecked item",
    );

    const tofuCard = itemCard(page, "Tofu");
    await tofuCard.getByRole("button").first().click();
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: "Tofu checked." }),
      "Expected tofu check toast",
    );
    await page.waitForFunction(
      () => [...document.querySelectorAll(".item-category-header h3")].some((node) => node.textContent?.includes("Checked off")),
    );
    await pageTwo.waitForFunction(
      () => {
        const card = [...document.querySelectorAll(".item-card")].find((node) =>
          node.textContent?.includes("Tofu"),
        );
        return Boolean(card && card.classList.contains("is-checked"));
      },
      { timeout: 5000 },
    );

    const eierCard = itemCard(page, "Eier");
    await eierCard.getByRole("button").first().click();
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: "Eier checked." }),
      "Expected Eier check toast",
    );
    await page.waitForFunction(
      () => {
        const groups = [...document.querySelectorAll(".item-category-group")];
        const checkedGroup = groups.find((group) =>
          group.querySelector(".item-category-header h3")?.textContent?.includes("Checked off"),
        );
        if (!checkedGroup) {
          return false;
        }
        const checkedNames = [...checkedGroup.querySelectorAll(".item-card .item-name")].map(
          (node) => node.textContent?.trim(),
        );
        return checkedNames[0] === "Eier" && checkedNames.includes("Tofu");
      },
      { timeout: 5000 },
    );
    const checkedNames = await textList(
      page.locator(".item-category-group:last-child .item-card .item-name"),
    );
    assert.equal(checkedNames[0], "Eier", "Most recently checked item should be first in checked section");
    assert(checkedNames.includes("Tofu"), "Expected previously checked item in checked section");
    await page.goto(listUrl, { waitUntil: "networkidle" });
    await expectVisible(
      page.locator(".item-category-header h3", { hasText: "Checked off" }),
      "Expected checked-off section before promotion screenshot",
    );
    await screenshot(page, "promotion-filled-list");

    const hackfleischCard = await revealCheckedItemCard(page, "Hackfleisch");
    await hackfleischCard.click();
    const hackfleischEditPanel = page.locator("[data-item-edit-panel]", { hasText: "Hackfleisch" });
    await expectVisible(hackfleischEditPanel, "Expected Hackfleisch edit modal before deleting");
    await hackfleischEditPanel.locator("[data-item-edit-delete]").click();
    await expectVisible(
      page.locator("[data-list-toast]", { hasText: /Hackfleisch (deleted|wurde gelöscht)\./ }),
      "Expected delete toast",
    );
    await page.locator("[data-list-toast-undo]").click();
    await expectVisible(
      page.locator(".item-card", { hasText: "Hackfleisch" }),
      "Undo should restore deleted item",
    );
    await page.goto(listUrl, { waitUntil: "networkidle" });
    await expectVisible(itemCard(page, "Tomaten"), "Expected Tomaten before promotion edit screenshot");

    await itemCard(page, "Tomaten").click();
    await expectVisible(
      page.locator("[data-item-edit-panel]").getByRole("heading", { name: "Tomaten" }),
      "Clicking item should open edit modal",
    );
    await screenshot(page, "promotion-edit-item-dialogue");
    const editSearch = editForm.locator("[data-item-edit-category-search]");
    await editSearch.fill("brot");
    await expectVisible(
      editForm.locator(".category-radio-option", { hasText: "Backwaren" }),
      "Alias search should find Backwaren",
    );
    const aliasTexts = await textList(
      editForm.locator(".category-radio-option .category-radio-copy span"),
    );
    assert(!aliasTexts.some((text) => text.includes("Also found as")), "Alias helper text should stay hidden");
    await expectHidden(
      editForm.getByRole("button", { name: "Save changes" }),
      "Edit modal should live-save without a save button",
    );
    await editForm.locator(".category-radio-option", { hasText: "Backwaren" }).click();
    await editForm.locator('input[name="quantity_text"]').fill("4 loaves");
    const editPanel = page.locator("[data-item-edit-panel]");
    const editHeader = editPanel.locator(".add-item-panel-header");
    await expectVisible(
      editHeader.locator("[data-item-edit-status]", { hasText: "Saved." }),
      "Expected quantity edit to live-save in the sticky header after debounce",
    );
    await editForm.locator('input[name="note"]').fill("for the weekend");
    await page.locator("[data-item-edit-panel] .add-item-close[data-item-edit-close]").click();
    await expectHidden(page.locator("[data-item-edit-overlay]"), "Immediate close should flush pending edit");
    await expectVisible(
      itemCard(page, "Tomaten").locator(".item-meta", { hasText: "for the weekend" }),
      "Close-triggered save should keep note edit",
    );
    await expectVisible(itemCard(page, "Tomaten"), "Updated item should remain visible");
    await expectVisible(
      itemCard(page, "Tomaten").locator(".item-meta", { hasText: "4 loaves" }),
      "Updated quantity should render",
    );
    await itemCard(page, "Tomaten").click();
    await expectVisible(
      page.locator("[data-item-edit-panel]").getByRole("heading", { name: "Tomaten" }),
      "Expected Tomaten edit modal before undoing a live edit",
    );
    await expectVisible(
      page.locator("[data-item-edit-header-actions]"),
      "Edit history controls and close button should stay in the sticky header",
    );
    const editHeaderMetrics = await editHeader.evaluate((header) => {
      const panel = header.closest("[data-item-edit-panel]");
      const undo = header.querySelector("[data-item-edit-undo]");
      const icon = undo?.querySelector(".item-edit-history-icon");
      const status = header.querySelector("[data-item-edit-status]");
      if (
        !(panel instanceof HTMLElement)
          || !(undo instanceof HTMLElement)
          || !(icon instanceof Element)
          || !(status instanceof HTMLElement)
      ) {
        return null;
      }
      const headerRect = header.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const undoRect = undo.getBoundingClientRect();
      const iconRect = icon.getBoundingClientRect();
      return {
        backgroundColor: window.getComputedStyle(header).backgroundColor,
        headerLeft: headerRect.left,
        headerRight: headerRect.right,
        headerTop: headerRect.top,
        iconHeight: iconRect.height,
        iconWidth: iconRect.width,
        panelLeft: panelRect.left,
        panelRight: panelRect.right,
        panelTop: panelRect.top,
        statusInHeader: status.closest(".add-item-panel-header") === header,
        undoHeight: undoRect.height,
        undoWidth: undoRect.width,
      };
    });
    assert(editHeaderMetrics, "Expected measurable edit header controls");
    assert(
      editHeaderMetrics.headerLeft <= editHeaderMetrics.panelLeft + 1
        && editHeaderMetrics.headerRight >= editHeaderMetrics.panelRight - 1,
      "Edit sticky header background should reach the panel edges",
    );
    assert(
      editHeaderMetrics.headerTop <= editHeaderMetrics.panelTop + 2,
      "Edit sticky header background should cover the panel top edge",
    );
    assert(
      editHeaderMetrics.backgroundColor !== "rgba(0, 0, 0, 0)",
      "Edit sticky header should have a visible background",
    );
    assert(
      editHeaderMetrics.undoWidth <= 44
        && editHeaderMetrics.undoHeight <= 40
        && editHeaderMetrics.iconWidth <= 18
        && editHeaderMetrics.iconHeight <= 18,
      "Edit history icons should stay compact",
    );
    assert(
      editHeaderMetrics.statusInHeader,
      "Live save status should belong to the sticky edit header",
    );
    await editForm.locator('input[name="quantity_text"]').fill("wrong amount");
    await expectVisible(
      editHeader.locator("[data-item-edit-status]", { hasText: "Saved." }),
      "Expected wrong quantity to live-save before undo",
    );
    await page.getByRole("button", { name: "Undo last edit" }).click();
    await page.waitForFunction(
      () => document.querySelector('[data-item-edit-form] input[name="quantity_text"]')?.value === "4 loaves",
      { timeout: 5000 },
    );
    await expectVisible(
      itemCard(page, "Tomaten").locator(".item-meta", { hasText: "4 loaves" }),
      "Undo should restore previous live-saved quantity",
    );
    await page.getByRole("button", { name: "Redo edit" }).click();
    await page.waitForFunction(
      () => document.querySelector('[data-item-edit-form] input[name="quantity_text"]')?.value === "wrong amount",
      { timeout: 5000 },
    );
    await page.getByRole("button", { name: "Undo last edit" }).click();
    await page.waitForFunction(
      () => document.querySelector('[data-item-edit-form] input[name="quantity_text"]')?.value === "4 loaves",
      { timeout: 5000 },
    );
    await page.locator("[data-item-edit-panel] .add-item-close[data-item-edit-close]").click();
    await expectHidden(page.locator("[data-item-edit-overlay]"), "Edit modal should close before opening settings");

    await page.getByRole("button", { name: "Add item" }).click();
    const moveThingName = `Move target ${Date.now()}`;
    await addForm.getByLabel("Item name").fill(moveThingName);
    await page.locator(".add-item-save-button").click();
    const moveThingCard = page.locator("[data-item-card]", { hasText: moveThingName }).first();
    await expectVisible(moveThingCard, "Expected move target item before moving");
    await moveThingCard.click();
    await expectVisible(
      page.locator("[data-item-edit-panel]").getByRole("heading", { name: moveThingName }),
      "Expected move target edit modal",
    );
    await editForm.getByLabel("Move to list").selectOption({ label: scenario.moveTargetListName });
    const movedNotice = page.locator("[data-moved-item-notice]", { hasText: moveThingName }).first();
    await expectVisible(
      movedNotice,
      "Expected moved-item undo notice where the item was",
    );
    await expectVisible(
      movedNotice.getByText(scenario.moveTargetListName),
      "Expected moved-item notice to include target list name",
    );
    const goToListLink = movedNotice.getByRole("link", { name: "Go to list" });
    await expectVisible(goToListLink, "Expected moved-item notice to link to the target list");
    assert.equal(
      new URL(await goToListLink.getAttribute("href"), baseUrl).pathname,
      `/lists/${scenario.moveTargetListId}`,
    );
    await expectHidden(moveThingCard, "Moved item should leave the source list");
    await pageTwo.waitForFunction(
      (name) => ![...document.querySelectorAll(".item-card .item-name")].some((node) => node.textContent?.trim() === name),
      moveThingName,
      { timeout: 5000 },
    );
    const moveTargetItems = await apiJson(context.request, `/api/v1/lists/${scenario.moveTargetListId}/items`);
    const movedTargetItem = moveTargetItems.find((item) => item.name === moveThingName);
    assert(movedTargetItem, "Expected moved item in target list");
    await movedNotice.getByRole("button", { name: "Undo" }).click();
    await expectVisible(moveThingCard, "Undo should restore moved item in the source list");
    const moveTargetItemsAfterUndo = await apiJson(context.request, `/api/v1/lists/${scenario.moveTargetListId}/items`);
    assert(
      !moveTargetItemsAfterUndo.some((item) => item.id === movedTargetItem.id),
      "Undo should remove moved item from the target list",
    );
    const sourceItemsAfterUndo = await apiJson(context.request, `/api/v1/lists/${scenario.listId}/items`);
    const restoredMoveItem = sourceItemsAfterUndo.find((item) => item.name === moveThingName);
    assert(restoredMoveItem, "Undo should move item back to the source list");
    await apiJson(context.request, `/api/v1/items/${restoredMoveItem.id}`, { method: "DELETE" });

    await page.getByRole("button", { name: "Open list settings" }).click();
    await expectVisible(page.getByRole("heading", { name: "Category order" }), "Expected settings modal");
    const settingsPanel = page.locator("[data-list-settings-panel]");
    const renamedListName = `E2E Market ${Date.now()}`;
    await settingsPanel.getByLabel("List name").fill(renamedListName);
    await settingsPanel.getByRole("button", { name: "Save list name" }).click();
    await expectVisible(
      page.locator("[data-list-success]", { hasText: "List name saved." }),
      "Expected list rename success",
    );
    await expectVisible(page.getByRole("heading", { name: renamedListName }), "List title should update");
    const renamedList = await apiJson(context.request, `/api/v1/lists/${scenario.listId}`);
    assert.equal(renamedList.name, renamedListName, "List rename should persist through the API");
    scenario.listName = renamedListName;
    await assertSeedSettingsCategoryColors(page);
    const topCategoryBefore = (
      await textList(page.locator(".item-category-group > .item-category-header h3"))
    ).slice(0, 3);
    assert.equal(topCategoryBefore[0], "Uncategorized", "Uncategorized should stay on top");

    const backwarenSettingsRow = page.locator(".settings-category-row", { hasText: "Backwaren" });
    for (let i = 0; i < 4; i += 1) {
      await backwarenSettingsRow.getByRole("button", { name: /Move Backwaren up/i }).click();
      await page.waitForTimeout(150);
    }
    await page.locator("[data-list-settings-panel] .add-item-close").click();

    await page.waitForFunction(
      () => {
        const headers = [...document.querySelectorAll(".item-category-group > .item-category-header h3")].map(
          (node) => node.textContent?.trim(),
        );
        return headers.indexOf("Backwaren") > -1 && headers.indexOf("Backwaren") < headers.indexOf("Nudeln");
      },
      { timeout: 5000 },
    );
    await pageTwo.waitForFunction(
      () => {
        const headers = [...document.querySelectorAll(".item-category-group > .item-category-header h3")].map(
          (node) => node.textContent?.trim(),
        );
        return headers.indexOf("Backwaren") > -1 && headers.indexOf("Backwaren") < headers.indexOf("Nudeln");
      },
      { timeout: 5000 },
    );

    const backwarenGroup = page
      .locator(".item-category-group")
      .filter({ has: page.locator(".item-category-header h3", { hasText: "Backwaren" }) })
      .first();
    await backwarenGroup.getByRole("button", { name: "Quick add to Backwaren" }).click();
    await expectVisible(page.locator("[data-item-panel]"), "Category quick add should open add modal");
    assert.equal(
      (await addForm
        .locator('.category-radio-option:has(input[name="category_id"]:checked) .category-radio-copy strong')
        .textContent())?.trim(),
      "Backwaren",
      "Category quick add should preselect that category",
    );
    const freshThingName = `Fresh thing ${Date.now()}`;
    await addForm.getByLabel("Item name").fill(freshThingName);
    await addForm.locator('input[name="quantity_text"]').fill("1");
    await page.locator(".add-item-save-button").click();
    const freshThingCard = itemCard(page, freshThingName);
    await expectVisible(freshThingCard, "Expected newly added item");
    await expectVisible(
      page.locator(".item-card.is-highlighted", { hasText: freshThingName }),
      "New item should be highlighted after saving",
    );
    await expectInViewport(freshThingCard, "New item should be scrolled into view after saving");
    await expectVisible(
      page
        .locator(".item-category-group", { hasText: "Backwaren" })
        .locator(".item-card", { hasText: freshThingName }),
      "New item should land in the Backwaren section",
    );

    await page.getByRole("button", { name: "Open list settings" }).click();
    await expectVisible(page.getByRole("heading", { name: "Category order" }), "Expected settings modal");
    const backwarenDisableRow = settingsPanel.locator(".settings-category-row", { hasText: "Backwaren" });
    await dragCategoryAfter(page, "Backwaren", "Nudeln");
    await backwarenDisableRow.getByRole("button", { name: /Disable Backwaren/i }).click();
    await expectVisible(
      page.locator("[data-category-disable-confirm-panel]", { hasText: "Disable Backwaren?" }),
      "Disabling a populated category should use the app confirmation modal",
    );
    await page.locator("[data-category-disable-confirm-confirm]").click();
    await expectVisible(
      backwarenDisableRow.locator(".settings-category-copy", { hasText: "Disabled for this list" }),
      "Disabled category should be visibly marked",
    );
    await page.locator("[data-list-settings-panel] .add-item-close").click();
    await page.waitForFunction(
      (name) => {
        const uncategorized = [...document.querySelectorAll(".item-category-group")].find((group) =>
          group.querySelector(".item-category-header h3")?.textContent?.includes("Uncategorized"),
        );
        return Boolean(
          uncategorized &&
            [...uncategorized.querySelectorAll(".item-card")].some((card) =>
              card.textContent?.includes(name),
            ),
        );
      },
      freshThingName,
      { timeout: 5000 },
    );
    await page.getByRole("button", { name: "Add item" }).click();
    const addMoreFields = addForm.locator(".item-more-fields");
    if (!(await addMoreFields.evaluate((node) => node.open))) {
      await addMoreFields.locator("summary").click();
    }
    await addForm.locator("[data-item-category-search]").fill("brot");
    await expectHidden(
      addForm.locator(".category-radio-option", { hasText: "Backwaren" }),
      "Disabled category should not be selectable when adding items",
    );
    await page.locator("[data-item-panel] .add-item-close").click();
    await page.getByRole("button", { name: "Open list settings" }).click();
    await settingsPanel
      .locator(".settings-category-row", { hasText: "Backwaren" })
      .getByRole("button", { name: /Enable Backwaren/i })
      .click();
    await page.locator("[data-list-settings-panel] .add-item-close").click();

    const toast = page.locator("[data-list-toast]");
    await freshThingCard.getByRole("button").first().click();
    await expectVisible(toast, "Expected temporary undo toast");
    await page.waitForTimeout(10500);
    await expectHidden(toast, "Undo toast should disappear after timeout");

    await runOfflineSyncFlow(page, context.request, scenario.listId);

    await runCheckedStressListFlow(page, checkedStressListUrl);

    await runInviteFlow(page, browser, scenario, seed, rpId);

    await screenshot(page, "ui-e2e-final");
    await screenshot(pageTwo, "ui-e2e-second-client");
    logStep("Browser UI e2e completed successfully");
  } catch (error) {
    logStep(`Browser UI e2e failed: ${error instanceof Error ? error.message : String(error)}`);
    if (page) {
      await screenshot(page, "ui-e2e-failure-main").catch(() => {});
    }
    throw error;
  } finally {
    if (browser) {
      await browser.close();
    }
  }

  const summary = [
    "## UI E2E",
    "",
    `Browser UI flow passed for ${deviceName} using seeded real database data and passkey auth for public support and privacy contacts, route rendering, login gating, multi-passkey enrollment and deletion, add/edit flows, fuzzy duplicate suggestions, undo toasts, category alias search, category disabling, admin navigation, websocket updates, and household invite acceptance.`,
    "",
  ].join("\n");
  await fs.writeFile(path.join(artifactDir, "summary.md"), summary);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
