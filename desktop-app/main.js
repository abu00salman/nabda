// Native desktop shell (Windows + macOS) around the live Nabda site.
//
// Same idea as android-app/: the window loads the real deployed page instead of a
// bundled copy, so every web deploy reaches desktop users too. This file only adds
// what a browser tab can't: its own window and icon, a single running instance,
// and strict navigation rules so the window never wanders off to another site.

const { app, BrowserWindow, session, shell } = require('electron');

const APP_URL = 'https://playnabda.com/';
const APP_HOST = 'playnabda.com';

// One window at a time. A second launch focuses the existing window instead.
if (!app.requestSingleInstanceLock()) {
  app.quit();
}

// Opens http(s) links in the user's real browser, never inside the game window.
function openExternal(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol === 'https:' || parsed.protocol === 'http:') {
      shell.openExternal(url);
    }
  } catch {
    // Malformed URL: nothing to open.
  }
}

// Only the game's own host may load inside the window.
function isAppUrl(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && parsed.hostname === APP_HOST;
  } catch {
    return false;
  }
}

// Shown when the first load fails (offline, DNS, server down). Inline so it works
// with no network at all. The button navigates back to the live site.
function errorPageUrl() {
  const html = `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html,body{margin:0;height:100%;background:#0E141B;color:#E8F1FF;
    font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center}
  .box{text-align:center;padding:24px}
  h1{font-size:20px;margin:0 0 8px}
  p{opacity:.7;margin:0 0 20px}
  button{background:#D4FF5A;color:#0E141B;border:0;border-radius:12px;
    padding:12px 24px;font-size:16px;font-weight:700;cursor:pointer}
</style></head><body><div class="box">
<h1>تعذّر الاتصال بنبضة</h1>
<p>تحقّق من الإنترنت ثم حاول مرة أخرى.</p>
<button onclick="location.href='${APP_URL}'">إعادة المحاولة</button>
</div></body></html>`;
  return 'data:text/html;charset=utf-8,' + encodeURIComponent(html);
}

function createWindow() {
  const win = new BrowserWindow({
    width: 480,
    height: 880,
    minWidth: 360,
    minHeight: 640,
    title: 'نبضة',
    backgroundColor: '#0E141B',
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      // The page never needs Node or any native API, so none is exposed to it.
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });

  win.once('ready-to-show', () => win.show());

  // Keep the game in this window. Any other address goes to the default browser.
  win.webContents.on('will-navigate', (event, url) => {
    if (!isAppUrl(url)) {
      event.preventDefault();
      openExternal(url);
    }
  });
  win.webContents.on('will-redirect', (event, url) => {
    if (!isAppUrl(url)) {
      event.preventDefault();
      openExternal(url);
    }
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    openExternal(url);
    return { action: 'deny' };
  });

  // A failed top-level load shows the native error page. Aborted loads (-3) are
  // normal when the user navigates away mid-load, so they are ignored.
  win.webContents.on('did-fail-load', (_event, errorCode, _desc, _url, isMainFrame) => {
    if (isMainFrame && errorCode !== -3) {
      win.loadURL(errorPageUrl()).catch(() => {});
    }
  });

  // The promise rejects on a failed load; did-fail-load above already handles that.
  win.loadURL(APP_URL).catch(() => {});
}

app.whenReady().then(() => {
  // The game needs no camera, mic, location, notifications, or other permissions.
  // Deny every request the page makes.
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    callback(false);
  });

  // Gives Windows the app's own identity for taskbar grouping and notifications.
  app.setAppUserModelId('com.playnabda.desktop');

  createWindow();

  app.on('activate', () => {
    // macOS: clicking the Dock icon with no open window reopens the game.
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('second-instance', () => {
  const [win] = BrowserWindow.getAllWindows();
  if (win) {
    if (win.isMinimized()) win.restore();
    win.focus();
  }
});

// Closing the last window quits everywhere except macOS, where apps stay in the Dock.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
