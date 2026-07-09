export function getNameCode(fullName) {
  if (!fullName || typeof fullName !== "string") {
    return "";
  }

  const nameParts = fullName.trim().split(/\s+/);

  // If candidate has first name and last name, use initials
  if (nameParts.length >= 2) {
    const firstInitial = nameParts[0][0] || "";
    const lastInitial = nameParts[1][0] || "";
    return `${firstInitial}${lastInitial}`.toUpperCase();
  }

  // If candidate has single name, use first two letters
  return nameParts[0].slice(0, 2).toUpperCase();
}

export function formatSerial(serialNo) {
  return String(serialNo).padStart(3, "0");
}

export function getYearCode(dateValue = new Date()) {
  return new Date(dateValue).getFullYear().toString().slice(-2);
}

export function generateMID(
  roleCode,
  nameCode,
  serialNo,
  yearCode = getYearCode()
) {
  if (!roleCode || !nameCode || !serialNo) {
    return "";
  }

  return `JCF-${roleCode}-${nameCode}-${yearCode}${formatSerial(serialNo)}`;
}

export function getNextSerial(roleCode, nameCode, midRegistry = []) {
  const matchingRecords = midRegistry.filter(
    (record) => record.roleCode === roleCode && record.nameCode === nameCode
  );

  if (matchingRecords.length === 0) {
    return 1;
  }

  const highestSerial = Math.max(
    ...matchingRecords.map((record) => record.serialNo)
  );

  return highestSerial + 1;
}

export function generateCandidateMID(candidate, midRegistry = []) {
  if (!candidate) {
    return "";
  }

  const roleCode = candidate.roleCode;
  const nameCode = getNameCode(candidate.fullName);
  const nextSerial = getNextSerial(roleCode, nameCode, midRegistry);

  return generateMID(roleCode, nameCode, nextSerial);
}
