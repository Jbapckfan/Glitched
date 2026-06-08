# Glitched Landing Site

Static launch site for Glitched.

## Preview Locally

From the repo root:

```bash
python3 -m http.server 8080 --directory marketing/site
```

Then open:

```text
http://localhost:8080
```

Opening `index.html` directly also works, but a local server is closer to GitHub Pages/Vercel behavior.

## Deploy

### GitHub Pages

1. Keep the built site in `marketing/site/`.
2. In GitHub Pages settings, publish from the branch/folder you choose.
3. If publishing from `/docs` is required, copy the contents of `marketing/site/` into that deployment folder in a later deploy-only branch.

### Vercel

1. Create a new Vercel project from the repo.
2. Set the project root to `marketing/site`.
3. No build command is required.
4. Output directory is `.`.

## Where Real Assets Go

Drop final captures here:

```text
marketing/site/assets/screenshots/iphone-6-7/
marketing/site/assets/screenshots/ipad/
marketing/site/assets/video/
marketing/site/assets/press/
```

Expected asset names:

```text
assets/video/app-preview-6-7.mov
assets/video/app-preview-ipad.mov
assets/screenshots/iphone-6-7/shot-01-dark-mode.png
assets/screenshots/iphone-6-7/shot-02-screenshot-freeze.png
assets/screenshots/iphone-6-7/shot-03-rotate.png
assets/screenshots/iphone-6-7/shot-04-time-travel.png
assets/screenshots/iphone-6-7/shot-05-charging.png
assets/screenshots/iphone-6-7/shot-06-brightness.png
assets/screenshots/iphone-6-7/shot-07-meta.png
assets/screenshots/iphone-6-7/shot-08-flashlight-or-multitouch.png
assets/press/press-kit.zip
```

Replace the CSS-only showcase panels in `index.html` with real GIF/video loops after capture.

## Notes

- No backend is included.
- The email form is intentionally a stub. Connect Buttondown, Mailchimp, ConvertKit, or a static form endpoint before publishing.
- The App Store badge slot is a placeholder. Replace it with Apple's official badge asset and live App Store URL after the app page is available.
