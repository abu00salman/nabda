package com.playnabda.app

import android.content.Intent
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.webkit.ConsoleMessage
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import com.playnabda.app.databinding.ActivityMainBinding

/**
 * The entire native shell. One Activity, one WebView, pointed at the real deployed
 * site (BuildConfig.BASE_URL) rather than a bundled copy of it.
 *
 * Nabda already ships a service worker (sw.js) that precaches the app shell and its
 * static assets, and the leaderboard is a server-side Cloudflare Worker + KV store —
 * both already work exactly the same from inside a WebView as they do in a browser
 * tab. Bundling a second copy of index.html into the APK would only mean the app
 * silently serves a stale build until someone remembers to rebuild and re-publish it,
 * independent of ordinary web deploys to playnabda.com. So this file is strictly what
 * a browser tab cannot do on its own: a real app icon/splash, edge-to-edge layout,
 * back-button semantics that pause an active round instead of exiting, and a native
 * fallback for the one failure a page can't render its own error screen for (the
 * top-level navigation failing before it ever loaded).
 *
 * There is no @JavascriptInterface bridge here (contrast with a more complex WebView
 * shell that needs one): the page never needs to call into native code, so the only
 * native→web communication is a one-way `evaluateJavascript` read of
 * `window.__nabdaDebug.S` to decide what the Back button should do, and a synthetic
 * 'p' keydown reusing the page's own existing pause toggle
 * (`if (e.code === 'Escape' || e.key === 'p') S.paused ? resume() : pause();` in
 * index.html) — never a new code path on the web side.
 */
class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    // Derived from BASE_URL rather than a second BuildConfig constant, so pointing a
    // debug build at a local dev server can't leave the "is this navigation
    // same-origin" check out of sync with where the app actually loaded.
    private val baseHost: String? by lazy { Uri.parse(BuildConfig.BASE_URL).host }

    private var pageReady = false

    private val backCallback =
        object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Ask the page whether a round is actively running before deciding what
                // Back should do — pausing beats accidentally exiting mid-round, but
                // Back should behave normally (exit / navigate history) everywhere else,
                // including when an overlay like the leaderboard or settings sheet is
                // open (those close via their own buttons, same as on the web).
                binding.webView.evaluateJavascript(
                    "(function(){try{var S=window.__nabdaDebug&&window.__nabdaDebug.S;" +
                        "return S&&S.running&&!S.paused&&!S.over?'pause':'';}catch(e){return '';}})()",
                ) { result ->
                    if (result == "\"pause\"") {
                        dispatchSyntheticPause()
                    } else if (binding.webView.canGoBack()) {
                        binding.webView.goBack()
                    } else {
                        isEnabled = false
                        onBackPressedDispatcher.onBackPressed()
                    }
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        super.onCreate(savedInstanceState)
        splashScreen.setKeepOnScreenCondition { !pageReady }
        // Safety net: never let a slow first load hold the splash screen up forever.
        // The loading spinner (shown below) takes over past this point instead.
        Handler(Looper.getMainLooper()).postDelayed({ pageReady = true }, 2500)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        configureWebView()
        onBackPressedDispatcher.addCallback(this, backCallback)

        binding.errorRetryButton.setOnClickListener {
            binding.errorOverlay.visibility = View.GONE
            binding.loadingSpinner.visibility = View.VISIBLE
            binding.webView.reload()
        }

        binding.webView.loadUrl(BuildConfig.BASE_URL)
    }

    override fun onResume() {
        super.onResume()
        binding.webView.onResume()
        binding.webView.resumeTimers()
    }

    override fun onPause() {
        binding.webView.onPause()
        binding.webView.pauseTimers()
        super.onPause()
    }

    override fun onDestroy() {
        (binding.webView.parent as? android.view.ViewGroup)?.removeView(binding.webView)
        binding.webView.destroy()
        super.onDestroy()
    }

    // ---------- WebView setup ----------

    private fun configureWebView() {
        val webView = binding.webView
        // Ensures canvas (the game ring) and CSS animations composite through the GPU
        // layer rather than falling back to software rendering, which some OEM WebView
        // builds default to under certain conditions.
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            // Best score, nickname, theme, device id, sound/mode preference all live in
            // localStorage (see index.html's `store` helper) — without this they'd
            // silently fail to persist between launches.
            databaseEnabled = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = false
            // No file:// access of any kind — the game has no file picker and reads
            // nothing from the filesystem.
            allowFileAccess = false
            allowContentAccess = false
            // A fixed, app-like layout: the system's font-scale accessibility setting
            // would otherwise distort the game's precisely-sized ring and HUD
            // independently of the page's own (already responsive) sizing.
            textZoom = 100
        }

        webView.webViewClient =
            object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    if (uri.host == baseHost) return false
                    openExternalLink(uri)
                    return true
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    pageReady = true
                    binding.loadingSpinner.visibility = View.GONE
                    binding.errorOverlay.visibility = View.GONE
                }

                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    pageReady = true
                    if (request.isForMainFrame) showErrorOverlay(isHttp = false)
                }

                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                    pageReady = true
                    if (request.isForMainFrame && errorResponse.statusCode >= 400) showErrorOverlay(isHttp = true)
                }

                // Deliberately NOT overridden to call handler.proceed() anywhere — the
                // default (handler.cancel(), failing the load) is exactly the required
                // behavior, so this override exists only as a visible, explicit record
                // of that choice rather than leaving it implicit.
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel()
                }
            }

        webView.webChromeClient =
            object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) {
                    // Nabda has no use for camera/mic/sensors — deny everything by
                    // default rather than prompting the user for access nothing needs.
                    request.deny()
                }

                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    if (BuildConfig.DEBUG) {
                        Log.d(TAG, "${message.message()} (${message.sourceId()}:${message.lineNumber()})")
                    }
                    return true
                }
            }

        webView.setDownloadListener { url, _, _, _, _ -> openExternalLink(Uri.parse(url)) }
    }

    // ---------- Back button ----------

    private fun dispatchSyntheticPause() {
        binding.webView.evaluateJavascript(
            "window.dispatchEvent(new KeyboardEvent('keydown',{key:'p',bubbles:true}))",
            null,
        )
    }

    // ---------- Errors ----------

    private fun showErrorOverlay(isHttp: Boolean) {
        binding.loadingSpinner.visibility = View.GONE
        binding.errorTitle.text = getString(if (isHttp) R.string.http_error_title else R.string.error_title)
        binding.errorBody.text = getString(if (isHttp) R.string.http_error_body else R.string.error_body)
        binding.errorOverlay.visibility = View.VISIBLE
    }

    // ---------- External links ----------

    private fun openExternalLink(uri: Uri) {
        runCatching {
            CustomTabsIntent.Builder().build().launchUrl(this, uri)
        }.onFailure {
            runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
        }
    }

    companion object {
        private const val TAG = "PlayNabda"
    }
}
