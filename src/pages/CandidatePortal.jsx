import { BriefcaseBusiness } from "lucide-react";

import { useAuth } from "../context/authContext";

const PORTAL_MODULES = ["Profile", "Leave", "Signed Offer", "Performance"];

export default function CandidatePortal() {
  const { user, candidateId } = useAuth();

  return (
    <main className="app-page">
      <header className="page-header-modern">
        <div className="page-icon" aria-hidden="true">
          <BriefcaseBusiness />
        </div>
        <div>
          <h1 className="page-title-modern">Candidate Portal</h1>
          <p className="page-subtitle">Your secure candidate workspace.</p>
        </div>
      </header>

      <section className="card" aria-labelledby="candidate-account-title">
        <h2 id="candidate-account-title">Account</h2>
        <p>
          Signed in as <strong>{user?.email || "Unknown account"}</strong>
        </p>
        <span className="badge badge-success">Portal account active</span>
      </section>

      <section className="card" aria-labelledby="candidate-reference-title">
        <h2 id="candidate-reference-title">Candidate reference</h2>
        <p>
          Candidate ID: <code>{candidateId}</code>
        </p>
      </section>

      <section aria-labelledby="candidate-modules-title">
        <h2 id="candidate-modules-title">Workspace</h2>
        <div className="module-grid">
          {PORTAL_MODULES.map((moduleName) => (
            <article className="card" key={moduleName}>
              <h3>{moduleName}</h3>
              <span className="badge badge-info">Coming next</span>
            </article>
          ))}
        </div>
      </section>

      <p className="page-subtitle" role="note">
        Self-service modules will appear here after candidate-specific access policies are enabled.
      </p>
    </main>
  );
}
