import { useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  addTextNote, addVoiceNote, answerQuestion, enrich, generateQuestions, generateReport,
  getEvent, getReflection, observations, questions, reports, saveTextReflection, saveVoiceReflection,
} from "../lib/db";
import type { EventRow, FollowupQuestion, Observation, Reflection, Report } from "../lib/types";
import { PHASES, type CapturePhase } from "../lib/types";
import { ErrorText, Loading, Markdown, Spinner, TopBar } from "../components/ui";
import { RecordButton } from "../components/RecordButton";

type Section = "notes" | "reflect" | "report";

export default function EventDetail() {
  const { eventId } = useParams();
  const nav = useNavigate();
  const [ev, setEv] = useState<EventRow | null>(null);
  const [section, setSection] = useState<Section>("notes");
  const [err, setErr] = useState("");

  useEffect(() => {
    if (eventId) getEvent(eventId).then(setEv).catch((e) => setErr((e as Error).message));
  }, [eventId]);

  if (!eventId) return null;
  if (err) return <div className="app"><div className="screen"><ErrorText>{err}</ErrorText></div></div>;
  if (!ev) return <Loading />;

  return (
    <div className="app">
      <TopBar title={ev.title} eyebrow={ev.event_type.replace("_", " ")}
        right={<button className="btn ghost sm" onClick={() => nav("/")}>Done</button>} />
      <div className="screen stack">
        {(ev.focus_area || ev.purpose || ev.hoping_to_see.length > 0) && (
          <div className="card">
            {ev.focus_area && <div><span className="muted small">Focus:</span> {ev.focus_area}</div>}
            {ev.purpose && <div><span className="muted small">Purpose:</span> {ev.purpose}</div>}
            {ev.hoping_to_see.length > 0 && (
              <div className="tags" style={{ marginTop: 8 }}>
                {ev.hoping_to_see.map((h, i) => <span key={i} className="tag">{h}</span>)}
              </div>
            )}
          </div>
        )}

        <div className="chipset">
          {(["notes", "reflect", "report"] as Section[]).map((s) => (
            <button key={s} className={`chip ${section === s ? "on" : ""}`} onClick={() => setSection(s)}>
              {s === "notes" ? "Notes" : s === "reflect" ? "Reflect" : "Report"}
            </button>
          ))}
        </div>

        {section === "notes" && <Notes eventId={eventId} teamId={ev.team_id} />}
        {section === "reflect" && <Reflect eventId={eventId} />}
        {section === "report" && <ReportSection ev={ev} />}
      </div>
    </div>
  );
}

// ---- Notes ------------------------------------------------------------------
function Notes({ eventId, teamId }: { eventId: string; teamId: string | null }) {
  const [list, setList] = useState<Observation[] | null>(null);
  const [phase, setPhase] = useState<CapturePhase>("live");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const load = useCallback(() => {
    observations(eventId).then(setList).catch((e) => setErr((e as Error).message));
  }, [eventId]);
  useEffect(() => { load(); }, [load]);

  const saveText = async () => {
    if (!text.trim()) return;
    setBusy(true); setErr("");
    try { await addTextNote(eventId, teamId, phase, text.trim()); setText(""); setTimeout(load, 600); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  const saveVoice = async (blob: Blob) => {
    setErr("");
    try { await addVoiceNote(eventId, teamId, phase, blob); load(); }
    catch (e) { setErr((e as Error).message); }
  };

  return (
    <>
      <div className="card stack">
        <div className="chipset">
          {PHASES.map((p) => (
            <button key={p.value} className={`chip ${phase === p.value ? "on" : ""}`} onClick={() => setPhase(p.value)}>
              {p.label}
            </button>
          ))}
        </div>
        <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a quick note…" />
        <div className="row">
          <button className="btn" onClick={saveText} disabled={busy || !text.trim()}>
            {busy ? <Spinner /> : "Add note"}
          </button>
          <div className="spacer" />
        </div>
        <div style={{ borderTop: "1px solid var(--faint)", paddingTop: 12 }}>
          <RecordButton onComplete={saveVoice} label="…or record a voice note" />
        </div>
        <ErrorText>{err}</ErrorText>
      </div>

      {list === null ? <Loading /> : (
        <div className="list">
          {list.map((o) => (
            <div key={o.id} className={`card note ${o.sentiment}`}>
              <div className="muted small" style={{ marginBottom: 2 }}>
                {PHASES.find((p) => p.value === o.capture_phase)?.label}
                {o.input_type === "voice_note" ? " · voice" : ""}
              </div>
              <div>{o.cleaned_note ?? o.raw_note ?? <span className="muted">Transcribing…</span>}</div>
              {o.tags?.length > 0 && (
                <div className="tags">{o.tags.map((t, i) => <span key={i} className="tag">{t}</span>)}</div>
              )}
            </div>
          ))}
          {list.length === 0 && <div className="card muted">No notes yet. Capture the first one above.</div>}
        </div>
      )}
      {list && list.length > 0 && (
        <button className="btn ghost block sm" onClick={load}>Refresh</button>
      )}
    </>
  );
}

// ---- Reflect ----------------------------------------------------------------
function Reflect({ eventId }: { eventId: string }) {
  const [ref, setRef] = useState<Reflection | null>(null);
  const [text, setText] = useState("");
  const [qs, setQs] = useState<FollowupQuestion[]>([]);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string>("");
  const [err, setErr] = useState("");

  const load = useCallback(async () => {
    try {
      const r = await getReflection(eventId);
      setRef(r);
      if (r) { setText(r.raw_transcript ?? ""); setQs(await questions(r.id)); }
    } catch (e) { setErr((e as Error).message); }
  }, [eventId]);
  useEffect(() => { load(); }, [load]);

  const save = async () => {
    setBusy("save"); setErr("");
    try { const r = await saveTextReflection(eventId, text.trim()); setRef(r); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };

  const saveVoice = async (blob: Blob) => {
    setBusy("voice"); setErr("");
    try { const r = await saveVoiceReflection(eventId, blob); setRef(r); setTimeout(load, 800); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };

  const getQuestions = async () => {
    if (!ref) return;
    setBusy("questions"); setErr("");
    try { await generateQuestions(ref.id); setQs(await questions(ref.id)); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };

  const weave = async () => {
    if (!ref) return;
    setBusy("enrich"); setErr("");
    try {
      for (const q of qs) {
        const a = answers[q.id]?.trim();
        if (a) await answerQuestion(q.id, a);
      }
      await enrich(ref.id);
      await load();
    } catch (e) { setErr((e as Error).message); }
    finally { setBusy(""); }
  };

  return (
    <>
      <div className="card stack">
        <h2 className="serif">Your reflection</h2>
        <p className="muted small">Write or record what the session was like. Keep it in your own words. This
          is a mirror, not a mark.</p>
        <textarea value={text} onChange={(e) => setText(e.target.value)} rows={5}
          placeholder="How did it go? What stood out?" />
        <div className="row">
          <button className="btn" onClick={save} disabled={busy === "save" || !text.trim()}>
            {busy === "save" ? <Spinner /> : ref ? "Update" : "Save reflection"}
          </button>
        </div>
        <div style={{ borderTop: "1px solid var(--faint)", paddingTop: 12 }}>
          <RecordButton onComplete={saveVoice} label="…or record your reflection" />
        </div>
        <ErrorText>{err}</ErrorText>
      </div>

      {ref?.enriched_summary && (
        <div className="card">
          <div className="eyebrow" style={{ marginBottom: 6 }}>With your added context</div>
          <p>{ref.enriched_summary}</p>
        </div>
      )}

      {ref && (
        <div className="card stack">
          <div className="row">
            <h2 className="serif">A little more?</h2>
            <div className="spacer" />
            <button className="btn subtle sm" onClick={getQuestions} disabled={busy === "questions"}>
              {busy === "questions" ? <Spinner /> : qs.length ? "Refresh questions" : "Ask me questions"}
            </button>
          </div>
          <p className="muted small">Optional, skippable prompts to add a little context where it's thin.</p>
          {qs.map((q) => (
            <div key={q.id} className="field">
              <label>{q.question_text}</label>
              <input value={answers[q.id] ?? ""} onChange={(e) => setAnswers((a) => ({ ...a, [q.id]: e.target.value }))}
                placeholder="Optional…" />
            </div>
          ))}
          {qs.length > 0 && (
            <button className="btn" onClick={weave} disabled={busy === "enrich"}>
              {busy === "enrich" ? <Spinner /> : "Weave in my answers"}
            </button>
          )}
        </div>
      )}
    </>
  );
}

// ---- Report -----------------------------------------------------------------
function ReportSection({ ev }: { ev: EventRow }) {
  const [list, setList] = useState<Report[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const load = useCallback(() => {
    reports(ev.id).then(setList).catch((e) => setErr((e as Error).message));
  }, [ev.id]);
  useEffect(() => { load(); }, [load]);

  const gen = async () => {
    setBusy(true); setErr("");
    try { await generateReport(ev.id, ev.event_type); load(); }
    catch (e) { setErr((e as Error).message); }
    finally { setBusy(false); }
  };

  return (
    <>
      <div className="card stack">
        <p className="muted small">A report organises what you and your notes actually said, and never grades
          you. Generate one once you've captured notes and reflected.</p>
        <button className="btn" onClick={gen} disabled={busy}>
          {busy ? <Spinner /> : "Generate report"}
        </button>
        <ErrorText>{err}</ErrorText>
      </div>

      {list === null ? <Loading /> : list.map((r) => (
        <div key={r.id} className="card">
          {r.content_markdown ? <Markdown text={r.content_markdown} /> : <span className="muted">Empty report.</span>}
        </div>
      ))}
    </>
  );
}
