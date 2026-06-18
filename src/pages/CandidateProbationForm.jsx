import { useState } from "react";
import { Link } from "react-router-dom";
import { submitCandidateForm } from "../services/candidateFormService";

const initialFormData = {
  full_name: "",
  email: "",
  phone: "",
  address: "",
  applied_role: "",
  role_code: "",
  department: "",
  candidate_consent: false,
};

export default function CandidateProbationForm() {
  const [formData, setFormData] = useState(initialFormData);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [successMessage, setSuccessMessage] = useState("");
  const [errorMessage, setErrorMessage] = useState("");

  function handleChange(event) {
    const { checked, name, type, value } = event.target;

    setFormData((currentFormData) => ({
      ...currentFormData,
      [name]: type === "checkbox" ? checked : value,
    }));
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setSuccessMessage("");
    setErrorMessage("");

    if (!formData.candidate_consent) {
      setErrorMessage("Candidate consent is required.");
      return;
    }

    setIsSubmitting(true);

    try {
      await submitCandidateForm({
        ...formData,
        source: "Candidate Form",
      });

      setFormData(initialFormData);
      setSuccessMessage("Candidate submitted successfully and moved to HR review pending.");
    } catch (error) {
      console.error("Unable to submit candidate form:", error);
      setErrorMessage(error.message || "Unable to submit candidate form.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div style={{ padding: "20px" }}>
      <h1>Candidate Probation Form</h1>

      <form onSubmit={handleSubmit}>
        <input
          name="full_name"
          placeholder="Full Name"
          value={formData.full_name}
          onChange={handleChange}
          required
        />
        <br /><br />

        <input
          name="email"
          placeholder="Email"
          type="email"
          value={formData.email}
          onChange={handleChange}
          required
        />
        <br /><br />

        <input
          name="phone"
          placeholder="Phone"
          value={formData.phone}
          onChange={handleChange}
        />
        <br /><br />

        <input
          name="address"
          placeholder="Address"
          value={formData.address}
          onChange={handleChange}
        />
        <br /><br />

        <input
          name="applied_role"
          placeholder="Role Applied For"
          value={formData.applied_role}
          onChange={handleChange}
        />
        <br /><br />

        <input
          name="role_code"
          placeholder="Role Code"
          value={formData.role_code}
          onChange={handleChange}
        />
        <br /><br />

        <input
          name="department"
          placeholder="Department"
          value={formData.department}
          onChange={handleChange}
        />
        <br /><br />

        <label>
          <input
            name="candidate_consent"
            type="checkbox"
            checked={formData.candidate_consent}
            onChange={handleChange}
          />
          Candidate Consent
        </label>

        <br /><br />

        <button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Submitting..." : "Submit"}
        </button>
      </form>

      {successMessage && <p>{successMessage}</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <br />

      <Link to="/">
        <button>Back to Dashboard</button>
      </Link>
    </div>
  );
}
