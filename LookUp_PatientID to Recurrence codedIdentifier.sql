

-- ** This select query pulls out the PatientIDs and their matching 'CodedIdentifier' 
-- ** that was used by Alez Newsham during the validation.
SELECT DISTINCT ex_CodedIdentifier, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL