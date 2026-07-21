import { useRef, useState } from "react";
import { Recorder, micSupported } from "../lib/recorder";
import { Spinner } from "./ui";

// Tap to start/stop recording; on stop, hands the audio blob to onComplete
// (which uploads + transcribes). Shows a clear message if the mic is blocked.
export function RecordButton({
  onComplete, label = "Hold a thought — record",
}: { onComplete: (blob: Blob) => Promise<void>; label?: string }) {
  const rec = useRef(new Recorder());
  const [on, setOn] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  if (!micSupported()) {
    return <p className="muted small">Voice recording isn’t supported on this device — type your note instead.</p>;
  }

  const toggle = async () => {
    setErr("");
    if (!on) {
      try { await rec.current.start(); setOn(true); }
      catch { setErr("Microphone blocked. Allow mic access in your browser settings to record."); }
    } else {
      setOn(false); setBusy(true);
      try {
        const blob = await rec.current.stop();
        await onComplete(blob);
      } catch (e) { setErr((e as Error).message); }
      finally { setBusy(false); }
    }
  };

  return (
    <div className="stack" style={{ alignItems: "center", gap: 8 }}>
      <button className={`record ${on ? "on" : ""}`} onClick={toggle} disabled={busy} aria-label={on ? "Stop" : "Record"}>
        {busy ? <Spinner /> : on ? (
          <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2" /></svg>
        ) : (
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <rect x="9" y="2" width="6" height="12" rx="3" /><path d="M5 10a7 7 0 0 0 14 0M12 17v4" />
          </svg>
        )}
      </button>
      <span className="muted small">{busy ? "Transcribing…" : on ? "Recording — tap to stop" : label}</span>
      {err && <p className="error">{err}</p>}
    </div>
  );
}
