import { useState } from "react";
import { Link } from "react-router-dom";
import { submitCandidateForm } from "../services/candidateFormService";
import { UserPlus } from "lucide-react";

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
  <div className="form-page">

    <div className="form-card">
    <Link to="/" className="back-link">
  ← Back to Dashboard
</Link>

<div className="form-header">

  <div className="form-header-icon">
    <UserPlus size={28} />
  </div>

  <div>
    <h1>Candidate Probation Form</h1>

    <p>
      Submit candidate details for HR review and probation workflow
    </p>
  </div>

</div>


      <form onSubmit={handleSubmit}>


        <div className="form-grid">


          <div className="form-group">
          <h3 className="form-section-title">
  Candidate Information
</h3>
            <label>
  Full Name
  <span className="required">*</span>
</label>

            <input
              name="full_name"
              placeholder="Enter full name"
              value={formData.full_name}
              onChange={handleChange}
              required
            />
          </div>



          <div className="form-group">
            <label>
  Email
  <span className="required">*</span>
</label>

            <input
              name="email"
              type="email"
              placeholder="Enter email"
              value={formData.email}
              onChange={handleChange}
              required
            />
          </div>




          <div className="form-group">
            <label>Phone</label>

            <input
              name="phone"
              placeholder="Enter phone number"
              value={formData.phone}
              onChange={handleChange}
            />
          </div>




          <div className="form-group">
          <h3 className="form-section-title">
  Position Details
</h3>
            <label>Department</label>

            <input
              name="department"
              placeholder="Department"
              value={formData.department}
              onChange={handleChange}
            />
          </div>




          <div className="form-group">
            <label>Applied Role</label>

            <input
              name="applied_role"
              placeholder="Role applied for"
              value={formData.applied_role}
              onChange={handleChange}
            />
          </div>




          <div className="form-group">
            <label>Role Code</label>

            <input
              name="role_code"
              placeholder="Role code"
              value={formData.role_code}
              onChange={handleChange}
            />
          </div>


        </div>



        <div className="form-group">
        <h3 className="form-section-title">
  Additional Information
</h3>

          <label>Address</label>

          <textarea

            name="address"

            placeholder="Enter address"

            value={formData.address}

            onChange={handleChange}

          />

        </div>





        <div className="checkbox-row consent-box">

          <input

            type="checkbox"

            name="candidate_consent"

            checked={formData.candidate_consent}

            onChange={handleChange}

          />


          <span>
            Candidate has provided consent
          </span>

        </div>





        <button
  className="btn btn-success submit-btn"

          type="submit"

          disabled={isSubmitting}

        >

          {
            isSubmitting
            ? "Submitting..."
            : "Submit Candidate"
          }


        </button>



      </form>





      {successMessage && (

        <div className="success-message">

          {successMessage}

        </div>

      )}





      {errorMessage && (

        <div className="error-message">

          {errorMessage}

        </div>

      )}







    </div>

  </div>
);
}
