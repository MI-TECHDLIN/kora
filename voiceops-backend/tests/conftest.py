"""
Shared pytest setup.

Offline tests always run. Tests that need the outside world carry a marker and are skipped by
default with a visible reason (`pytest -rs`, on in pytest.ini):

    live         needs a running backend or a real third-party service. Opt in with
                 `pytest --run-live` or VOICEOPS_RUN_LIVE=1.
    audio        needs a sound device. Skipped when sounddevice/PortAudio is unusable.
    credentials  `@pytest.mark.credentials("assemblyai_api_key")` skips unless each named
                 app.config setting is non-empty.

Files named `live_*.py` are manual scripts, not tests, and are never collected.
"""
import os
from importlib import metadata

import pytest

# pytest-asyncio 0.23.0 crashes during collection on pytest 8.x, which is why the plugin was once
# switched off. 0.23.8 is the pin in requirements.txt.
MIN_PYTEST_ASYNCIO = (0, 23, 8)


def _version_tuple(version: str) -> tuple:
    parts = []
    for piece in version.split(".")[:3]:
        digits = "".join(ch for ch in piece if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def pytest_addoption(parser):
    parser.addoption(
        "--run-live",
        action="store_true",
        default=False,
        help="also run tests marked 'live' (real network, running backend, paid services)",
    )


def pytest_configure(config):
    try:
        installed = metadata.version("pytest-asyncio")
    except metadata.PackageNotFoundError:
        return
    if _version_tuple(installed) < MIN_PYTEST_ASYNCIO:
        raise pytest.UsageError(
            f"pytest-asyncio {installed} is too old for this suite (it crashes on collection). "
            "Run: pip install -r requirements.txt"
        )


def _run_live(config) -> bool:
    return config.getoption("--run-live") or os.getenv("VOICEOPS_RUN_LIVE") == "1"


_audio_problem = None


def audio_problem() -> str:
    """Why no sound device is usable, or an empty string when one is."""
    global _audio_problem
    if _audio_problem is None:
        try:
            import sounddevice as sd

            if not any(d.get("max_output_channels", 0) > 0 for d in sd.query_devices()):
                _audio_problem = "no audio output device"
            else:
                _audio_problem = ""
        except (ImportError, OSError) as exc:  # OSError: PortAudio library not found
            _audio_problem = f"sounddevice unavailable ({exc})"
        except Exception as exc:
            _audio_problem = f"cannot query audio devices ({exc})"
    return _audio_problem


def pytest_collection_modifyitems(config, items):
    from app.config import settings

    run_live = _run_live(config)
    for item in items:
        if item.get_closest_marker("live") and not run_live:
            item.add_marker(pytest.mark.skip(
                reason="live test: needs a running backend or a real service; use --run-live or VOICEOPS_RUN_LIVE=1"
            ))
        if item.get_closest_marker("audio"):
            problem = audio_problem()
            if problem:
                item.add_marker(pytest.mark.skip(reason=f"audio test: {problem}"))
        for marker in item.iter_markers("credentials"):
            missing = [name for name in marker.args if not getattr(settings, name, None)]
            if missing:
                item.add_marker(pytest.mark.skip(
                    reason=f"credentials test: {', '.join(missing)} not configured"
                ))


@pytest.fixture(autouse=True)
def _fresh_eta_cache():
    """The app-wide `eta_service` keeps its traffic ETA cache for the life of the process."""
    from app.services.eta_service import eta_service

    eta_service.clear_cache()
    yield
    eta_service.clear_cache()
