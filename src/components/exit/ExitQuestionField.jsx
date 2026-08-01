/**
 * ExitQuestionField.jsx
 * A single question renderer. Supports: rating, nps, dropdown, multiselect,
 * textarea, radio, and readonly (auto-filled) types.
 *
 * Props:
 *   id        – unique HTML id for the input
 *   label     – displayed question label
 *   type      – "rating" | "nps" | "dropdown" | "multiselect" | "textarea" | "radio" | "readonly"
 *   options   – [{ value, label }] for dropdown / multiselect / radio
 *   required  – bool
 *   value     – current value (string | string[] | number)
 *   onChange  – (value) => void  — receives the new value directly
 *   hint      – optional helper text
 *   error     – validation error string
 *   ratingMax – for "rating" type (default 5)
 */

import { RATING_SCALE, NPS_SCALE } from "../../constants/exitFormOptions";

export default function ExitQuestionField({
  id,
  label,
  type,
  options = [],
  required = false,
  value,
  onChange,
  hint,
  error,
  ratingMax = 5,
}) {
  const fieldId = id;
  const labelEl = (
    <label
      htmlFor={type === "multiselect" || type === "rating" || type === "nps" ? undefined : fieldId}
      style={{ fontWeight: 600, display: "block", marginBottom: 6 }}
    >
      {label}
      {required && (
        <span className="required" aria-hidden="true">
          {" "}*
        </span>
      )}
    </label>
  );

  const hintEl = hint ? (
    <p id={`${fieldId}-hint`} style={{ margin: "4px 0 0", fontSize: 13, color: "#64748b" }}>
      {hint}
    </p>
  ) : null;

  const errorEl = error ? (
    <p id={`${fieldId}-error`} role="alert" style={{ margin: "4px 0 0", fontSize: 13, color: "#dc2626" }}>
      {error}
    </p>
  ) : null;

  // ----- READONLY (auto-filled) -----
  if (type === "readonly") {
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <div
          style={{
            background: "#f8fafc",
            border: "1px solid #e2e8f0",
            borderRadius: 10,
            padding: "11px 14px",
            color: "#0f172a",
            fontSize: 15,
          }}
          aria-readonly="true"
        >
          {value || <span style={{ color: "#94a3b8" }}>—</span>}
        </div>
        {hintEl}
      </div>
    );
  }

  // ----- STAR RATING (1–5) -----
  if (type === "rating") {
    const scale = ratingMax === 5 ? RATING_SCALE : Array.from({ length: ratingMax }, (_, i) => i + 1);
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <div
          role="radiogroup"
          aria-labelledby={`${fieldId}-label`}
          aria-required={required}
          style={{ display: "flex", gap: 8, flexWrap: "wrap" }}
        >
          <span id={`${fieldId}-label`} style={{ display: "none" }}>{label}</span>
          {scale.map((n) => (
            <button
              key={n}
              type="button"
              aria-label={`Rate ${n} out of ${scale[scale.length - 1]}`}
              aria-pressed={value === n || value === String(n)}
              onClick={() => onChange(n)}
              style={{
                width: 44,
                height: 44,
                borderRadius: 10,
                border: "2px solid",
                borderColor: (value === n || value === String(n)) ? "#2563eb" : "#e2e8f0",
                background: (value === n || value === String(n)) ? "#2563eb" : "white",
                color: (value === n || value === String(n)) ? "white" : "#334155",
                fontWeight: 700,
                fontSize: 16,
                cursor: "pointer",
                transition: "all 0.15s ease",
              }}
            >
              {n}
            </button>
          ))}
        </div>
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- NPS (0–10) -----
  if (type === "nps") {
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <div
          role="radiogroup"
          aria-labelledby={`${fieldId}-nps-label`}
          aria-required={required}
          style={{ display: "flex", gap: 6, flexWrap: "wrap" }}
        >
          <span id={`${fieldId}-nps-label`} style={{ display: "none" }}>{label}</span>
          {NPS_SCALE.map((n) => (
            <button
              key={n}
              type="button"
              aria-label={`Score ${n} out of 10`}
              aria-pressed={value === n || value === String(n)}
              onClick={() => onChange(n)}
              style={{
                width: 42,
                height: 42,
                borderRadius: 8,
                border: "2px solid",
                borderColor:
                  value === n || value === String(n)
                    ? npsColor(n)
                    : "#e2e8f0",
                background:
                  value === n || value === String(n) ? npsColor(n) : "white",
                color: (value === n || value === String(n)) ? "white" : "#334155",
                fontWeight: 700,
                fontSize: 14,
                cursor: "pointer",
                transition: "all 0.15s ease",
              }}
            >
              {n}
            </button>
          ))}
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "#94a3b8", marginTop: 4 }}>
          <span>Not at all likely</span>
          <span>Extremely likely</span>
        </div>
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- DROPDOWN -----
  if (type === "dropdown") {
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <select
          id={fieldId}
          className="form-select"
          value={value || ""}
          onChange={(e) => onChange(e.target.value)}
          required={required}
          aria-describedby={
            [hint ? `${fieldId}-hint` : "", error ? `${fieldId}-error` : ""]
              .filter(Boolean)
              .join(" ") || undefined
          }
          style={{ width: "100%", padding: "11px", borderRadius: 8, border: "1px solid #cbd5e1", fontSize: 15 }}
        >
          <option value="">Select an option…</option>
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- MULTISELECT (checkbox group) -----
  if (type === "multiselect") {
    const selected = Array.isArray(value) ? value : [];
    const toggle = (v) => {
      const next = selected.includes(v)
        ? selected.filter((x) => x !== v)
        : [...selected, v];
      onChange(next);
    };
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <div
          role="group"
          aria-labelledby={`${fieldId}-group-label`}
          style={{ display: "flex", flexDirection: "column", gap: 8 }}
        >
          <span id={`${fieldId}-group-label`} style={{ display: "none" }}>{label}</span>
          {options.map((o) => (
            <label
              key={o.value}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                cursor: "pointer",
                fontWeight: "normal",
                padding: "8px 12px",
                borderRadius: 8,
                border: "1px solid",
                borderColor: selected.includes(o.value) ? "#2563eb" : "#e2e8f0",
                background: selected.includes(o.value) ? "#eff6ff" : "white",
                transition: "all 0.15s ease",
              }}
            >
              <input
                type="checkbox"
                style={{ width: "auto", margin: 0, accentColor: "#2563eb" }}
                checked={selected.includes(o.value)}
                onChange={() => toggle(o.value)}
                aria-label={o.label}
              />
              {o.label}
            </label>
          ))}
        </div>
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- RADIO -----
  if (type === "radio") {
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <div
          role="radiogroup"
          aria-labelledby={`${fieldId}-radio-label`}
          style={{ display: "flex", flexDirection: "column", gap: 8 }}
        >
          <span id={`${fieldId}-radio-label`} style={{ display: "none" }}>{label}</span>
          {options.map((o) => (
            <label
              key={o.value}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                cursor: "pointer",
                fontWeight: "normal",
                padding: "9px 12px",
                borderRadius: 8,
                border: "1px solid",
                borderColor: value === o.value ? "#2563eb" : "#e2e8f0",
                background: value === o.value ? "#eff6ff" : "white",
                transition: "all 0.15s ease",
              }}
            >
              <input
                type="radio"
                name={fieldId}
                value={o.value}
                style={{ width: "auto", margin: 0, accentColor: "#2563eb" }}
                checked={value === o.value}
                onChange={() => onChange(o.value)}
                aria-label={o.label}
              />
              {o.label}
            </label>
          ))}
        </div>
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- SINGLE LINE TEXT INPUT -----
  if (type === "text") {
    return (
      <div className="form-group" style={{ marginBottom: 18 }}>
        {labelEl}
        <input
          type="text"
          id={fieldId}
          value={value || ""}
          onChange={(e) => onChange(e.target.value)}
          required={required}
          aria-describedby={
            [hint ? `${fieldId}-hint` : "", error ? `${fieldId}-error` : ""]
              .filter(Boolean)
              .join(" ") || undefined
          }
          style={{
            width: "100%",
            padding: "11px",
            borderRadius: 8,
            border: "1px solid #cbd5e1",
            fontSize: 15,
            fontFamily: "inherit",
          }}
        />
        {hintEl}
        {errorEl}
      </div>
    );
  }

  // ----- TEXTAREA (default) -----
  return (
    <div className="form-group" style={{ marginBottom: 18 }}>
      {labelEl}
      <textarea
        id={fieldId}
        rows={4}
        value={value || ""}
        onChange={(e) => onChange(e.target.value)}
        required={required}
        aria-describedby={
          [hint ? `${fieldId}-hint` : "", error ? `${fieldId}-error` : ""]
            .filter(Boolean)
            .join(" ") || undefined
        }
        style={{
          width: "100%",
          padding: "11px",
          borderRadius: 8,
          border: "1px solid #cbd5e1",
          fontSize: 15,
          fontFamily: "inherit",
          resize: "vertical",
        }}
      />
      {hintEl}
      {errorEl}
    </div>
  );
}

// NPS colour helper — red for detractors, yellow for passives, green for promoters
function npsColor(n) {
  if (n <= 6) return "#dc2626";
  if (n <= 8) return "#f59e0b";
  return "#16a34a";
}
