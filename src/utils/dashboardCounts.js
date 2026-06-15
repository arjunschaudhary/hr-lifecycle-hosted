export function getDashboardCounts({
  candidates = [],
  probationAttempts = [],
  offers = [],
  activeInterns = [],
  signedOffers = [],
}) {
  return {
    totalCandidates: candidates.length,

    inProbation: candidates.filter(
      (candidate) => candidate.currentStatus === "IN_PROBATION"
    ).length,

    probationPassed: probationAttempts.filter(
      (attempt) => attempt.status === "PROBATION_PASSED"
    ).length,

    probationRejected: probationAttempts.filter(
      (attempt) => attempt.status === "PROBATION_REJECTED"
    ).length,

    probationExtended: probationAttempts.filter(
      (attempt) => attempt.status === "PROBATION_EXTENDED"
    ).length,

    offerLetterGenerated: offers.filter(
      (offer) => offer.offerStatus === "OFFER_LETTER_GENERATED"
    ).length,

    offerLetterSent: offers.filter(
      (offer) => offer.offerStatus === "OFFER_LETTER_SENT"
    ).length,

    activeInterns: activeInterns.filter(
      (intern) => intern.status === "ACTIVE"
    ).length,

    signedOfferSubmitted: signedOffers.filter(
      (signedOffer) => signedOffer.status === "SUBMITTED"
    ).length,

    signedOfferMismatch: signedOffers.filter(
      (signedOffer) =>
        signedOffer.emailMatchStatus === "MISMATCH" ||
        signedOffer.phoneMatchStatus === "MISMATCH"
    ).length,

    signedOfferRejected: signedOffers.filter(
      (signedOffer) => signedOffer.status === "REJECTED"
    ).length,
  };
}