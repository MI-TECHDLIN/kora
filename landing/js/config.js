/*
 * Site configuration. This is the only file to edit when a release exists.
 *
 * androidUrl: where the Android build downloads from, for example the APK
 * attached to a GitHub release:
 *   https://github.com/MI-TECHDLIN/kora/releases/latest/download/kora.apk
 * Leave it empty until then: every "Try Kora on Android" button then shows a
 * visible "coming soon" state instead of a dead link.
 *
 * demoReelUrl: an external embed for the demo reel section (clip-demo-reel),
 * used instead of the packaged assets/media/clip-demo-reel.mp4 once it is set,
 * for example a YouTube upload:
 *   https://www.youtube-nocookie.com/embed/<VIDEO_ID>
 * It must already be an embeddable player URL (the youtube-nocookie.com "embed/"
 * form, not a watch link), because it renders in an iframe. Leave it empty to
 * keep serving the packaged file. _headers' CSP allows youtube-nocookie.com in
 * frame-src for this; a different host needs that CSP updated too.
 */
export const CONFIG = {
  androidUrl: "",
  demoReelUrl: "",
};
