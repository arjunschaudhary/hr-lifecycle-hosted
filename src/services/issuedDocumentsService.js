import { supabase } from "./supabaseClient";

export async function fetchCurrentCandidateIssuedDocuments() {
  const { data, error } = await supabase.rpc("get_current_candidate_issued_documents");
  if (error || !Array.isArray(data)) throw new Error("Unable to load issued documents.");
  return data;
}

export async function getIssuedDocumentUrl(storagePath) {
  const { data, error } = await supabase.storage
    .from("candidate-issued-documents")
    .createSignedUrl(storagePath, 60);
  if (error || !data?.signedUrl) throw new Error("Unable to open issued document.");
  return data.signedUrl;
}
