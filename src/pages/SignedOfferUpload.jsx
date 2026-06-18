import { useState } from "react";
import { Link } from "react-router-dom";
import { submitSignedOfferUpload } from "../services/signedOfferUploadService";

const initialFormData = {
  mid: "",
  email: "",
  phone: "",
};

export default function SignedOfferUpload() {
  const [formData, setFormData] = useState(initialFormData);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [successMessage, setSuccessMessage] = useState("");
  const [errorMessage, setErrorMessage] = useState("");

  function handleChange(event) {
    const { name, value } = event.target;

    setFormData((currentFormData) => ({
      ...currentFormData,
      [name]: value,
    }));
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setSuccessMessage("");
    setErrorMessage("");
    setIsSubmitting(true);

    try {
      const result = await submitSignedOfferUpload(formData);

      setFormData(initialFormData);
      setSuccessMessage(
        result.status === "SIGNED_OFFER_SUBMITTED"
          ? "Signed offer submitted successfully."
          : "Signed offer submitted and moved to mismatch review."
      );
    } catch (error) {
      console.error("Unable to submit signed offer:", error);
      setErrorMessage(error.message || "Unable to submit signed offer.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div style={{ padding: "20px" }}>
      <h1>Signed Offer Upload</h1>

      <form onSubmit={handleSubmit}>
        <input
          name="mid"
          placeholder="MID"
          value={formData.mid}
          onChange={handleChange}
          required
        />
        <br /><br />

        <input
          name="email"
          placeholder="Registered Email"
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
          required
        />
        <br /><br />

        <button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Submitting..." : "Submit Signed Offer"}
        </button>
      </form>

      {successMessage && <p>{successMessage}</p>}

      {errorMessage && <p>{errorMessage}</p>}

      <Link to="/">
        <button>Back to Dashboard</button>
      </Link>
    </div>
  );
}
