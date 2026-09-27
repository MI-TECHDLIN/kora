/*
 * "Choose Kora's voice": mirrors the app's post-sign-up voice step
 * (frontend/lib/features/voice_onboarding/screens/voice_onboarding_screen.dart,
 * character art via widgets/voice_character_rive.dart) - characters grouped
 * by accent, the selected one ringed, and a single preview bar below
 * ("<Name> - Tap to hear a short preview") rather than a play button per
 * card. Selecting a character never autoplays audio; the bar's button does,
 * on tap, and loads nothing before that.
 */

import { VOICES, GROUP_LABELS, DEFAULT_VOICE, voiceAssetFor, voiceById } from "./voices.js";
import { characterSvg } from "./voice_characters.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const ic = (name, cls = "") => `<svg class="i ${cls}" aria-hidden="true" focusable="false"><use href="assets/icons.svg#i-${name}"/></svg>`;

/**
 * Mounts the picker into `root` (the element with [data-voice-picker], which
 * must contain [data-voice-groups] and [data-voice-bar]). Returns
 * `{ onSelect(fn), stop() }`; `onSelect` fires once immediately with the
 * default voice, then again on every change.
 */
export function initVoicePicker(root) {
  const groups = $("[data-voice-groups]", root);
  const bar = $("[data-voice-bar]", root);
  const live = document.querySelector("[data-voice-live]");

  groups.innerHTML = Object.keys(GROUP_LABELS)
    .map((group) => {
      const voices = VOICES.filter((v) => v.group === group);
      return `
      <div class="voice-group">
        <p class="voice-group__label">${GROUP_LABELS[group]}</p>
        <ul class="voice-grid">
          ${voices
            .map(
              (v) => `
            <li class="voice-card" data-voice="${v.id}">
              <button type="button" class="voice-card__btn" data-voice="${v.id}" aria-pressed="false">
                <span class="voice-card__avatar">${characterSvg(v)}</span>
                <span class="voice-card__label">${v.label}</span>
              </button>
            </li>`,
            )
            .join("")}
        </ul>
      </div>`;
    })
    .join("");

  bar.innerHTML = `
    <span class="voice-bar__avatar"></span>
    <span class="voice-bar__text">
      <b class="voice-bar__name"></b>
      <span class="voice-bar__hint"></span>
    </span>
    <button type="button" class="voice-bar__play" data-act="play"></button>`;
  const barAvatar = $(".voice-bar__avatar", bar);
  const playBtn = $(".voice-bar__play", bar);

  let selected = DEFAULT_VOICE;
  let playing = null;
  let announcedStop = true;
  const unavailable = new Set();
  const listeners = new Set();
  let audio = null;

  function getAudio() {
    if (audio) return audio;
    audio = new Audio();
    audio.preload = "none";
    audio.addEventListener("ended", () => {
      playing = null;
      render();
    });
    audio.addEventListener("error", () => {
      if (playing) unavailable.add(playing);
      playing = null;
      render();
    });
    return audio;
  }

  function stop() {
    if (audio) {
      audio.pause();
      audio.removeAttribute("src");
    }
    if (playing) {
      playing = null;
      render();
    }
  }

  function play(id) {
    if (playing === id) return stop();
    if (unavailable.has(id)) return;
    const el = getAudio();
    el.pause();
    el.src = voiceAssetFor(id);
    playing = id;
    render();
    el.play().catch(() => {
      unavailable.add(id);
      playing = null;
      render();
    });
  }

  function select(id) {
    if (selected === id) return;
    if (playing) stop();
    selected = id;
    render();
    const v = voiceById(id);
    for (const fn of listeners) fn(v);
  }

  function render() {
    for (const li of $$(".voice-card", groups)) {
      const id = li.dataset.voice;
      const isSelected = id === selected;
      const isSpeaking = id === playing;
      li.classList.toggle("is-selected", isSelected);
      $(".voice-card__btn", li).setAttribute("aria-pressed", String(isSelected));
      const svg = $(".vchar", li);
      if (svg) {
        svg.classList.toggle("is-selected", isSelected);
        svg.classList.toggle("is-speaking", isSpeaking);
      }
    }

    const v = voiceById(selected);
    const isPlaying = playing === selected;
    const isUnavailable = unavailable.has(selected);
    barAvatar.innerHTML = characterSvg(v, { selected: true, speaking: isPlaying });
    $(".voice-bar__name", bar).textContent = v.label;
    $(".voice-bar__hint", bar).textContent = isUnavailable
      ? "Preview unavailable"
      : isPlaying
        ? "Playing…"
        : "Tap to hear a short preview";
    playBtn.disabled = isUnavailable;
    playBtn.setAttribute("aria-pressed", String(isPlaying));
    playBtn.setAttribute(
      "aria-label",
      isUnavailable ? `${v.label}'s preview is unavailable` : isPlaying ? `Stop ${v.label}'s voice` : `Hear ${v.label}'s voice`,
    );
    playBtn.innerHTML = ic(isPlaying ? "player-pause" : "player-play");

    if (isPlaying) {
      live.textContent = `Playing ${v.label}.`;
      announcedStop = false;
    } else if (!announcedStop) {
      live.textContent = "Stopped.";
      announcedStop = true;
    }
  }

  groups.addEventListener("click", (e) => {
    const btn = e.target.closest(".voice-card__btn");
    if (!btn) return;
    select(btn.dataset.voice);
  });
  bar.addEventListener("click", (e) => {
    if (e.target.closest("[data-act='play']")) play(selected);
  });

  render();

  return {
    onSelect(fn) {
      listeners.add(fn);
      fn(voiceById(selected));
      return () => listeners.delete(fn);
    },
    stop,
  };
}
