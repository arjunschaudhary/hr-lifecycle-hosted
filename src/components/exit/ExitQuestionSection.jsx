/**
 * ExitQuestionSection.jsx
 * Wraps a logical section of the exit questionnaire with a title + border.
 * Matches the .form-section-title and .card patterns used across the project.
 */

export default function ExitQuestionSection({ id, title, children }) {
  return (
    <section
      className="card"
      aria-labelledby={id}
      style={{ marginBottom: 24 }}
    >
      <h2
        id={id}
        className="form-section-title"
        style={{ marginTop: 0 }}
      >
        {title}
      </h2>
      {children}
    </section>
  );
}
