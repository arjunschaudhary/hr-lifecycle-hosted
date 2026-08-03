import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  Menu,
  UserPlus,
  ClipboardCheck,
  FileSignature,
  BriefcaseBusiness,
  Upload,
  BadgeCheck,
  History,
  Users,
  Clock3,
  Search,
  FileText,
  PenSquare,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  RefreshCw,
  CalendarClock,
  Gauge,
  Network,
} from "lucide-react";

import {
  dummyCandidates,
  dummyProbationAttempts,
  dummyOffers,
  dummyActiveInterns,
  dummySignedOffers,
} from "../data";

import { getDashboardCounts } from "../utils/dashboardCounts";
import { fetchDashboardCounts } from "../services/hrDashboardService";
import { useAuth } from "../context/authContext";


function buildFallbackDashboardCounts() {

  const dummyCounts = getDashboardCounts({
    candidates: dummyCandidates,
    probationAttempts: dummyProbationAttempts,
    offers: dummyOffers,
    activeInterns: dummyActiveInterns,
    signedOffers: dummySignedOffers,
  });


  return {

    totalCandidates: dummyCounts.totalCandidates,

    hrReviewPending:
      dummyCandidates.filter(
        c => c.currentStatus === "HR_REVIEW_PENDING"
      ).length,


    inProbation:
      dummyCounts.inProbation,


    probationReview:
      dummyProbationAttempts.filter(
        a => a.status === "PROBATION_REVIEW"
      ).length,


    probationPassed:
      dummyCounts.probationPassed,


    probationRejected:
      dummyCounts.probationRejected,


    probationExtended:
      dummyCounts.probationExtended,


    offerLetterProcess:
      dummyOffers.filter(
        offer =>
        [
          "MID_GENERATED",
          "OFFER_LETTER_GENERATED"
        ].includes(offer.offerStatus)
      ).length,


    activeInterns:
      dummyCounts.activeInterns,


    signedOfferSubmitted:
      dummyCounts.signedOfferSubmitted,


    signedOfferVerified:
      dummySignedOffers.filter(
        offer =>
        [
          "SIGNED_OFFER_VERIFIED",
          "VERIFIED"
        ].includes(offer.status)
      ).length,


    mismatchReview:
      dummyCounts.signedOfferMismatch
  };
}




function MetricCard({title,value,icon}){

return (

<div className="metric-card">


<div className="metric-card__icon">
{icon}
</div>


<div>

<p className="metric-title">
{title}
</p>


<h2 className="metric-value">
{value}
</h2>


</div>


</div>

);

}






export default function HRDashboard(){

  const {
    hasPerformanceDashboardAccess,
    hasHrReviewAccess,
    hasPodManagementAccess,
  } = useAuth();

const fallbackCounts =
useMemo(
()=>buildFallbackDashboardCounts(),
[]
);



const [counts,setCounts]=
useState(fallbackCounts);


const [isLoading,setIsLoading]=
useState(true);


const [errorMessage,setErrorMessage]=
useState("");


const [showModules,setShowModules] =
useState(true);


useEffect(()=>{


let mounted=true;



async function load(){


try{


const result =
await fetchDashboardCounts();



if(!mounted) return;



if(result){

setCounts({
...fallbackCounts,
...result
});


setErrorMessage("");

}


else{


setCounts(fallbackCounts);

setErrorMessage(
"No dashboard data found. Showing demo data."
);

}


}

catch(err){


console.error(err);


setCounts(fallbackCounts);

setErrorMessage(
"Unable to load dashboard data."
);


}

finally{


if(mounted)
setIsLoading(false);


}


}



load();



return()=>mounted=false;


},[fallbackCounts]);

const cards = [
  [
    "Total Candidates",
    counts.totalCandidates,
    <Users size={22} />
  ],

  [
    "HR Review Pending",
    counts.hrReviewPending,
    <ClipboardCheck size={22} />
  ],

  [
    "In Probation",
    counts.inProbation,
    <Clock3 size={22} />
  ],

  [
    "Probation Review",
    counts.probationReview,
    <Search size={22} />
  ],

  [
    "Offer Process",
    counts.offerLetterProcess,
    <FileText size={22} />
  ],

  [
    "Active Interns",
    counts.activeInterns,
    <BriefcaseBusiness size={22} />
  ],

  [
    "Signed Offer Pending",
    counts.signedOfferSubmitted,
    <PenSquare size={22} />
  ],

  [
    "Verified Offers",
    counts.signedOfferVerified,
    <BadgeCheck size={22} />
  ],

  [
    "Mismatch Review",
    counts.mismatchReview,
    <AlertTriangle size={22} />
  ]
];

const decisions = [
  [
    "Passed",
    counts.probationPassed,
    <CheckCircle2 size={22} />
  ],

  [
    "Rejected",
    counts.probationRejected,
    <XCircle size={22} />
  ],

  [
    "Extended",
    counts.probationExtended,
    <RefreshCw size={22} />
  ]
];

const modules = [
  {
    path: "/candidate-form",
    label: "Candidate Form",
    icon: <UserPlus size={18} />,
  },
  {
    path: "/probation-review",
    label: "Probation Review",
    icon: <ClipboardCheck size={18} />,
  },
  {
    path: "/offer-approval",
    label: "Offer Process",
    icon: <FileSignature size={18} />,
  },
  {
    path: "/active-interns",
    label: "Active Interns",
    icon: <BriefcaseBusiness size={18} />,
  },
  {
    path: "/signed-offer-upload",
    label: "Signed Offer Upload",
    icon: <Upload size={18} />,
  },
  {
    path: "/signed-offer-verification",
    label: "Offer Verification",
    icon: <BadgeCheck size={18} />,
  },
  {
    path: "/activity-log",
    label: "Activity Logs",
    icon: <History size={18} />,
  },
  ...(hasPerformanceDashboardAccess
    ? [
        {
          path: "/performance-dashboard",
          label: "Performance Dashboard",
          icon: <Gauge size={18} />,
        },
      ]
    : []),
  ...(hasHrReviewAccess
    ? [
        {
          path: "/performance/hr-review",
          label: "HR Review",
          icon: <ClipboardCheck size={18} />,
        },
      ]
    : []),
  ...(hasPodManagementAccess
    ? [
        {
          path: "/pod-management",
          label: "Pod Management",
          icon: <Network size={18} />,
        },
      ]
    : []),
  {
    label: "Leave Dashboard",
    path: "/leave-dashboard",
  },
  {
    label: "Leave Application",
    path: "/leave-application",
  },
  {
    label: "Internship Extension",
    path: "/internship-extension",
    icon: <CalendarClock size={18} />,
  },
];

return (

<div className="dashboard-layout">
  <aside
  className={`sidebar ${
    showModules ? "" : "sidebar-collapsed"
  }`}
>

  <div className="sidebar-header">
    {showModules && <h2>Modules</h2>}
  </div>

  <div className="sidebar-menu">

    {modules.map((module) => (
      <Link
        key={module.path}
        to={module.path}
        className="sidebar-link"
      >
        <button
          className="sidebar-btn"
          title={module.label}
        >

          <span className="sidebar-icon">
            {module.icon}
          </span>

          {showModules && (
            <span className="sidebar-label">
              {module.label}
            </span>
          )}

        </button>
      </Link>
    ))}

  </div>

</aside>
  



  <main className="dashboard-content">
<div className="dashboard-header">

  <button
    className="sidebar-toggle"
    onClick={() => setShowModules(!showModules)}
  >
    <Menu size={22} />
  </button>

  <h1 className="dashboard-title">
    HR Dashboard
  </h1>

    <p className="dashboard-subtitle">
      Internship Lifecycle Management
    </p>

</div>

{isLoading &&
<div className="alert-card">
Loading dashboard...
</div>
}


{errorMessage &&
<div className="alert-card">
{errorMessage}
</div>
}


<h2 className="section-title">
  Lifecycle Overview
</h2>


<div className="metric-grid">


{

cards.map(
(item)=>(

<MetricCard

key={item[0]}

title={item[0]}

value={item[1]}

icon={item[2]}

/>

)

)

}


</div>





<h2 className="section-title">
  Probation Decisions
</h2>



<div className="metric-grid">


{

decisions.map(
(item)=>(

<MetricCard

key={item[0]}

title={item[0]}

value={item[1]}

icon={item[2]}

/>

)

)

}


</div>









</main>

</div>

);

}
