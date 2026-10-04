# Nothing project-specific to keep: this app has no @JavascriptInterface bridge (the
# web page never calls into native code — see README.md), so there is no reflection
# surface R8 could break by renaming/stripping. The default rules from
# proguard-android-optimize.txt are sufficient on their own.
