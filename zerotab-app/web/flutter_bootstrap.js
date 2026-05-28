{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function(engineInitializer) {
    // Use HTML renderer via bootstrap (--web-renderer flag removed in Flutter 3.22+).
    // Switch to "canvaskit" only for production builds needing pixel-perfect painting.
    const appRunner = await engineInitializer.initializeEngine({
      renderer: "html",
    });

    // Hide the loading indicator once Flutter fires its first frame
    window.addEventListener("flutter-first-frame", function () {
      const loader = document.getElementById("loading");
      if (loader) {
        loader.style.transition = "opacity 0.25s ease";
        loader.style.opacity = "0";
        setTimeout(() => loader.remove(), 280);
      }
    }, { once: true });

    await appRunner.runApp();
  },
});
