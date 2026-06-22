import { useState } from "react";
import { Link } from "react-router-dom";
import { Upload } from "lucide-react";
import { submitSignedOfferUpload } from "../services/signedOfferUploadService";


const initialFormData = {
  mid: "",
  email: "",
  phone: "",
};


export default function SignedOfferUpload() {

const [formData,setFormData] = useState(initialFormData);
const [isSubmitting,setIsSubmitting] = useState(false);
const [successMessage,setSuccessMessage] = useState("");
const [errorMessage,setErrorMessage] = useState("");



function handleChange(event){

const {name,value}=event.target;

setFormData(current=>({
...current,
[name]:value
}));

}



async function handleSubmit(event){

event.preventDefault();

setSuccessMessage("");
setErrorMessage("");

setIsSubmitting(true);


try{

const result =
await submitSignedOfferUpload(formData);


setFormData(initialFormData);


setSuccessMessage(
result.status==="SIGNED_OFFER_SUBMITTED"
?
"Signed offer submitted successfully."
:
"Signed offer submitted and moved to mismatch review."
);


}

catch(error){

console.error(error);

setErrorMessage(
error.message ||
"Unable to submit signed offer."
);

}


finally{

setIsSubmitting(false);

}

}





return (

<div className="form-page">


<div className="form-card">


<Link
to="/"
className="back-link"
>
← Back to Dashboard
</Link>



<div className="form-header">


<div className="form-header-icon">

<Upload size={28}/>

</div>



<div>

<h1>
Signed Offer Upload
</h1>


<p>
Submit signed offer details for verification workflow
</p>


</div>


</div>




<form onSubmit={handleSubmit}>


<div className="form-grid">



<div className="form-group">


<h3 className="form-section-title">
Candidate Verification
</h3>


<label>
MID
<span className="required">*</span>
</label>


<input

name="mid"

placeholder="Enter MID"

value={formData.mid}

onChange={handleChange}

required

/>

</div>





<div className="form-group">


<label>
Registered Email
<span className="required">*</span>
</label>


<input

type="email"

name="email"

placeholder="Enter registered email"

value={formData.email}

onChange={handleChange}

required

/>

</div>






<div className="form-group">


<label>
Phone
<span className="required">*</span>
</label>


<input

name="phone"

placeholder="Enter phone number"

value={formData.phone}

onChange={handleChange}

required

/>


</div>



</div>





<button

className="btn btn-success submit-btn"

type="submit"

disabled={isSubmitting}

>


{
isSubmitting
?
"Submitting..."
:
"Submit Signed Offer"
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