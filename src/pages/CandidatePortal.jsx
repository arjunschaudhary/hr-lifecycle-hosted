import { useEffect, useState } from "react";
import { BriefcaseBusiness } from "lucide-react";

import { useAuth } from "../context/authContext";
import { fetchCurrentCandidatePortalSummary } from "../services/candidatePortalService";

const formatValue = (value) => {
  if (value === null || value === undefined) {
    return "";
  }

  const normalizedValue = String(value).trim();
  return normalizedValue || "";
};

const formatStatus = (value) =>
  formatValue(value)
    .toLowerCase()
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");

const formatDate = (value) => {
  const normalizedValue = formatValue(value);

  if (!normalizedValue) {
    return "";
  }

  const date = /^\d{4}-\d{2}-\d{2}$/.test(normalizedValue)
    ? (() => {
        const [year, month, day] = normalizedValue.split("-").map(Number);
        return new Date(year, month - 1, day);
      })()
    : new Date(normalizedValue);

  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return new Intl.DateTimeFormat("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(date);
};

const formatDuration = (value) => {
  const duration = Number(value);

  if (!Number.isFinite(duration)) {
    return "";
  }

  return `${duration} month${duration === 1 ? "" : "s"}`;
};

function SummaryFields({ fields }) {
  const availableFields = fields.filter((field) => field.value);

  if (availableFields.length === 0) {
    return <p className="page-subtitle">No information available.</p>;
  }

  return (
    <div className="candidate-details-grid">
      {availableFields.map((field) => (
        <div className="candidate-detail-card" key={field.label}>
          <span>{field.label}</span>
          <strong>{field.value}</strong>
        </div>
      ))}
    </div>
  );
}

function SummaryCard({ title, children }) {
  return (
    <section className="card" aria-labelledby={`${title.toLowerCase().replaceAll(" ", "-")}-title`}>
      <h2 id={`${title.toLowerCase().replaceAll(" ", "-")}-title`}>{title}</h2>
      {children}
    </section>
  );
}

function PortalSummary({ summary }) {
  const profile = summary.profile;
  const internship = summary.internship;
  const leave = summary.leave;
  const signedOffer = summary.signedOffer;

  const profileFields = [
    { label: "Full Name", value: formatValue(profile.fullName) },
    { label: "Email", value: formatValue(profile.email) },
    { label: "Phone", value: formatValue(profile.phone) },
    { label: "Alternate Phone", value: formatValue(profile.alternatePhone) },
    { label: "Address", value: formatValue(profile.address) },
    { label: "City", value: formatValue(profile.city) },
    { label: "State", value: formatValue(profile.state) },
    { label: "Applied Role", value: formatValue(profile.appliedRole) },
    { label: "Role Code", value: formatValue(profile.roleCode) },
    { label: "Department", value: formatValue(profile.department) },
    { label: "Qualification", value: formatValue(profile.qualification) },
    { label: "College", value: formatValue(profile.collegeName) },
    { label: "Availability", value: formatValue(profile.availabilityStatus) },
    { label: "MID", value: formatValue(profile.mid) },
  ];

  const internshipFields = [
    { label: "Start Date", value: formatDate(internship.startDate) },
    { label: "Current End Date", value: formatDate(internship.currentEndDate) },
    {
      label: "Internship Duration",
      value: formatDuration(internship.internshipDurationMonths),
    },
    { label: "Lifecycle Status", value: formatStatus(internship.lifecycleStatus) },
  ];

  const signedOfferFields = [
    {
      label: "Current Status",
      value: formatStatus(signedOffer.status) || "Not submitted",
    },
    { label: "Submitted Date", value: formatDate(signedOffer.submittedAt) },
    { label: "Verified Date", value: formatDate(signedOffer.verifiedAt) },
  ];

  return (
    <>
      <SummaryCard title="Personal Information">
        <SummaryFields fields={profileFields} />
      </SummaryCard>

      <SummaryCard title="Internship Information">
        <SummaryFields fields={internshipFields} />
      </SummaryCard>

      <SummaryCard title="Leave Summary">
        {leave.available ? (
          <SummaryFields
            fields={[
              { label: "Allocated Leave", value: formatValue(leave.allocatedLeaveDays) },
              { label: "Approved Leave", value: formatValue(leave.approvedLeaveDays) },
              { label: "Remaining Leave", value: formatValue(leave.remainingLeaveDays) },
              { label: "Extra Leave", value: formatValue(leave.extraLeaveDays) },
            ]}
          />
        ) : (
          <p>Leave balance not available.</p>
        )}
      </SummaryCard>

      <SummaryCard title="Signed Offer">
        <SummaryFields fields={signedOfferFields} />
        <button className="btn btn-primary" type="button" disabled>
          Submit Signed Offer
        </button>
        <p className="page-subtitle">
          Secure signed-offer upload will be enabled after file storage is configured.
        </p>
      </SummaryCard>

      <SummaryCard title="Performance">
        <span className="badge badge-info">Coming next</span>
      </SummaryCard>
    </>
  );
}

export default function CandidatePortal() {
  const { user, candidateId } = useAuth();
  const [summary, setSummary] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [retryKey, setRetryKey] = useState(0);

  useEffect(() => {
    let isMounted = true;

    const loadSummary = async () => {
      try {
        const nextSummary = await fetchCurrentCandidatePortalSummary();

        if (!isMounted) {
          return;
        }

        setSummary(nextSummary);
        setError("");
      } catch (loadError) {
        if (!isMounted) {
          return;
        }

        setSummary(null);
        setError(
          loadError instanceof Error
            ? loadError.message
            : "Unable to load your candidate portal summary.",
        );
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    };

    void loadSummary();

    return () => {
      isMounted = false;
    };
  }, [retryKey]);

  const handleRetry = () => {
    setLoading(true);
    setError("");
    setSummary(null);
    setRetryKey((currentKey) => currentKey + 1);
  };

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

      {loading && (
        <section className="card" role="status" aria-live="polite">
          <p>Loading candidate portal summary...</p>
        </section>
      )}

      {!loading && error && (
        <section className="card" role="alert" aria-labelledby="candidate-summary-error-title">
          <h2 id="candidate-summary-error-title">Portal summary unavailable</h2>
          <p>{error}</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      )}

      {!loading && !error && !summary && (
        <section className="card" aria-labelledby="candidate-summary-empty-title">
          <h2 id="candidate-summary-empty-title">No portal summary available</h2>
          <p>Candidate information is not available yet.</p>
          <button className="btn btn-primary" type="button" onClick={handleRetry}>
            Retry
          </button>
        </section>
      )}

      {!loading && !error && summary && <PortalSummary summary={summary} />}
    </main>
  );
}
