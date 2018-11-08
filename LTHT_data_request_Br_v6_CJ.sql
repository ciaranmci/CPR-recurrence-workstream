CREATE PROCEDURE [recurrenceTables_Br]
AS
BEGIN

-- ***************************************************************
-- ** Create temporary table containing Patient IDs of interest.
-- ***************************************************************
begin -- 
DECLARE @WLbreast varchar(8) = '11003158';
IF OBJECT_ID ('tempdb..#breastPatients') IS NOT NULL  
	DROP TABLE #breastPatients;
CREATE TABLE #breastPatients(pID int);
INSERT INTO #breastPatients(pID)
SELECT DISTINCT wc_PatientID breastWatchlistPID
FROM PPMQuery.leeds.Watch
WHERE wc_WatchDefinitionID like @WLbreast
ORDER BY breastWatchlistPID;
--SELECT * FROM #breastPatients;
end--
-- ***************************************************************

-- ***************************************************************
-- ** Create temporary tables specific to each queried table.
-- ***************************************************************
begin -- ** PPMQuery.leeds.Consultations **
IF OBJECT_ID ('tempdb..#consultTable_Br_pre') IS NOT NULL  
	DROP TABLE #consultTable_Br_pre
CREATE TABLE #consultTable_Br_pre(
	   consIDkey uniqueidentifier, pID int, 
	   consultationDate date,
	   ageBandAtConsultationDate real,
	   consultantRole nvarchar(100),
	   consConsultantSpeciality nvarchar(100),
	   consSurvStatus bit,
	   consSurvTime real)
INSERT INTO #consultTable_Br_pre(
	   consIDkey, pID, 
	   consultationDate,
	   ageBandAtConsultationDate,
	   consultantRole,
	   consConsultantSpeciality,
	   consSurvStatus,
	   consSurvTime)
SELECT consIDkey, t1.pID,
		consultationDate,
		FLOOR(DATEDIFF(DAY,DOB,consultationDate)/(365.4*5)) ageBandAtConsultationDate,
		consultantRole,
		consConsultantSpeciality,
	   consSurvStatus,
	   consSurvTime
FROM
(SELECT newid() consIDkey, eb_PatientID pID,
	   eb_ConsultationDate consultationDate,
	   eb_ContactTypeLabel consultantRole,
	   eb_ContactSpecialityLabel consConsultantSpeciality,
	   eb_SurvivalStatus consSurvStatus,
	   eb_SurvivalTime consSurvTime
FROM PPMQuery.leeds.Consultations
WHERE eb_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, consultationDate DESC

IF OBJECT_ID ('tempdb..#consultTable_Br') IS NOT NULL  
	DROP TABLE #consultTable_Br
SELECT * INTO #consultTable_Br
FROM
(SELECT * FROM #consultTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier conspID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE consultationDate < '2012-04-13'
ALTER TABLE #consultTable_Br
DROP COLUMN pID, ex_PatientID
UPDATE #consultTable_Br SET ageBandAtConsultationDate = 17 WHERE ageBandAtConsultationDate > 17
--SELECT * FROM #consultTable_Br
end --

begin -- ** PPMQuery.leeds.Annotations **
IF OBJECT_ID ('tempdb..#annotationTable_Br_pre') IS NOT NULL  
	DROP TABLE #annotationsTable_Br_pre
CREATE TABLE #annotationsTable_Br_pre(
	   annotIDkey uniqueidentifier, pID int, 
	   dictateDate date,
		ageBandAtDictateDate real,
		annotationHeadline nvarchar(150))
INSERT INTO #annotationsTable_Br_pre(
	   annotIDkey, pID, 
	   dictateDate,
		ageBandAtDictateDate,
		annotationHeadline)
SELECT annotIDkey, t1.pID,
		dictateDate,
		FLOOR(DATEDIFF(DAY,DOB,dictateDate)/(365.4*5)) ageBandAtDictateDate,
		annotationHeadline
FROM
(SELECT newid() annotIDkey, an_PatientID pID, 
	   an_DictatedDate dictateDate,
	   an_Headline annotationHeadline
FROM PPMQuery.leeds.Annotations
WHERE an_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, dictateDate DESC

IF OBJECT_ID ('tempdb..#annotationTable_Br') IS NOT NULL  
	DROP TABLE #annotationsTable_Br
SELECT * INTO #annotationsTable_Br
FROM
(SELECT * FROM #annotationsTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier annotpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE (dictateDate < '2012-04-13')
ALTER TABLE #annotationsTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #annotationsTable_Br SET ageBandAtDictateDate = 17 WHERE ageBandAtDictateDate > 17
--SELECT * FROM #annotationsTable_Br
end --

begin -- **PPMQuery.leeds.Outpatients **
IF OBJECT_ID ('tempdb..#outpatientTable_Br_pre') IS NOT NULL  
	DROP TABLE #outpatientTable_Br_pre
CREATE TABLE #outpatientTable_Br_pre(
	   outpIDkey uniqueidentifier, pID int, 
	   clinicDate date,
	   clinicType nvarchar(100),
	   clinicContactType nvarchar(100),
	   ageBandAtClinicDate real,
	   outpContactSpeciality nvarchar(100),
	   ouptSurvStatus bit,
	   ouptSurvTime real)
INSERT INTO #outpatientTable_Br_pre(
	   outpIDkey, pID, 
	   clinicDate,
	   ageBandAtClinicDate,
	   clinicType,
	   clinicContactType,
	   outpContactSpeciality,
	   ouptSurvStatus,
	   ouptSurvTime)
SELECT outpIDkey, t1.pID,
		clinicDate,
		FLOOR(DATEDIFF(DAY,DOB,clinicDate)/(365.4*5)) ageBandAtClinicDate,
		clinicType,
		clinicContactType,
		outpContactSpeciality,
		ouptSurvStatus,
		ouptSurvTime
FROM
(SELECT newid() outpIDkey, op_PatientID pID, 
	   op_ClinicDate clinicDate,
	   op_ClinicType clinicType,
	   op_ActualContactTypeLabel clinicContactType,
	   op_ClinicConsultantContactSpecialityLabel outpContactSpeciality,
	   op_ActionStatusLabel,
	   op_SurvivalStatus ouptSurvStatus,
	   op_SurvivalTime ouptSurvTime
FROM PPMQuery.leeds.Outpatients
WHERE op_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, clinicDate DESC

IF OBJECT_ID ('tempdb..#outpatientTable_Br') IS NOT NULL  
	DROP TABLE #outpatientTable_Br
SELECT * INTO #outpatientTable_Br
FROM
(SELECT * FROM #outpatientTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier outppID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE clinicDate < '2012-04-13'
ALTER TABLE #outpatientTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #outpatientTable_Br SET ageBandAtClinicDate = 17 WHERE ageBandAtClinicDate > 17
-- SELECT * FROM #outpatientTable_Br
end --

begin -- ** PPMQuery.leeds.Admissions **
-- ** The first table has admissionDate. **
IF OBJECT_ID ('tempdb..#admissionsTable1_Br_pre') IS NOT NULL  
	DROP TABLE #admissionsTable1_Br_pre
CREATE TABLE #admissionsTable1_Br_pre(
	   pID1 int, 
	   admissionDate date,
	   ageBandAtAdmissionDate real,
	   admissionMethod nvarchar(100),
	   admissionDuration real,
	   admissionDurationLTHT real,
	   admissionSource nvarchar(200),
	   clinicianType nvarchar(100),
	   dischargeReason nvarchar(200),
	   admiConsultantSpeciality nvarchar(100),
	   admiSurvStatus bit,
	   admiSurvTime real)
INSERT INTO #admissionsTable1_Br_pre(
	   pID1, 
	   admissionDate,
	   ageBandAtAdmissionDate,
	   admissionMethod,
	   admissionDuration,
	   admissionDurationLTHT,
	   admissionSource,
	   clinicianType,
	   dischargeReason,
	   admiConsultantSpeciality,
	   admiSurvStatus,
	   admiSurvTime)
SELECT t1.pID1,
		admissionDate,
		FLOOR(DATEDIFF(DAY,DOB,admissionDate)/(365.4*5)) ageBandAtAdmissionDate,
		admissionMethod,
		DATEDIFF(DAY, admissionDate, dischargeDate) AS admissionDuration,
		admissionDurationLTHT,
		admissionSource,
		clinicianType,
		dischargeReason,
		admiConsultantSpeciality,
	   admiSurvStatus,
	   admiSurvTime
FROM
(SELECT em_PatientID pID1, 
	   em_AdmissionDate admissionDate,
	   em_DischargeDate dischargeDate,
	   em_Duration_plus_1 admissionDurationLTHT,
	   em_MethodLabel admissionMethod,
	   em_SourceLabel admissionSource,
	   em_ContactTypeLabel clinicianType,
	   em_DischargeMethodLabel dischargeReason,
	   em_ContactSpecialityLabel admiConsultantSpeciality,
	   em_SurvivalStatus admiSurvStatus,
	   em_SurvivalTime admiSurvTime
FROM PPMQuery.leeds.Admissions
WHERE em_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID1 = t2.pID
ORDER BY pID, admissionDate DESC

IF OBJECT_ID ('tempdb..#admissionsTable1_Br') IS NOT NULL  
	DROP TABLE #admissionsTable1_Br
SELECT * INTO #admissionsTable1_Br
FROM
(SELECT * FROM #admissionsTable1_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier admipID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID1 = t4.ex_PatientID
WHERE admissionDate < '2012-04-13'
ALTER TABLE #admissionsTable1_Br DROP COLUMN pID1, ex_PatientID
UPDATE #admissionsTable1_Br SET ageBandAtAdmissionDate = 17 WHERE ageBandAtAdmissionDate > 17
-- SELECT * FROM #admissionsTable1_Br ORDER BY admissionDate

-- ** The second table has dischageDate. **
IF OBJECT_ID ('tempdb..#admissionsTable2_Br_pre') IS NOT NULL  
	DROP TABLE #admissionsTable2_Br_pre
CREATE TABLE #admissionsTable2_Br_pre(
	   pID2 int, 
	   admissionMethod nvarchar(100),
	   dischargeDate date,
	   ageBandAtDischargeDate real,
	   admissionDuration real,
	   admissionDurationLTHT real,
	   admissionSource nvarchar(200),
	   clinicianType nvarchar(100),
	   dischargeReason nvarchar(200),
	   admiConsultantSpeciality nvarchar(100),
	   admiSurvStatus bit,
	   admiSurvTime real)
INSERT INTO #admissionsTable2_Br_pre(
	   pID2,
	   dischargeDate,
	   ageBandAtDischargeDate,
	   admissionMethod,
	   admissionDuration,
	   admissionDurationLTHT,
	   admissionSource,
	   clinicianType,
	   dischargeReason,
	   admiConsultantSpeciality,
	   admiSurvStatus,
	   admiSurvTime)
SELECT t1.pID2,
		dischargeDate,
		FLOOR(DATEDIFF(DAY,DOB,dischargeDate)/(365.4*5)) ageBandAtDischargeDate,
		admissionMethod,
		DATEDIFF(DAY, admissionDate, dischargeDate) AS admissionDuration,
		admissionDurationLTHT,
		admissionSource,
		clinicianType,
		dischargeReason,
		admiConsultantSpeciality,
		admiSurvStatus,
		admiSurvTime
FROM
(SELECT em_PatientID pID2,
	   em_MethodLabel admissionMethod,
	   em_AdmissionDate admissionDate,
	   em_DischargeDate dischargeDate,
	   em_Duration_plus_1 admissionDurationLTHT,
	   em_SourceLabel admissionSource,
	   em_ContactTypeLabel clinicianType,
	   em_DischargeMethodLabel dischargeReason,
	   em_ContactSpecialityLabel admiConsultantSpeciality,
	   em_SurvivalStatus admiSurvStatus,
	   em_SurvivalTime admiSurvTime
FROM PPMQuery.leeds.Admissions
WHERE em_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID, dischargeDate DESC

IF OBJECT_ID ('tempdb..#admissionsTable2_Br') IS NOT NULL  
	DROP TABLE #admissionsTable2_Br
SELECT * INTO #admissionsTable2_Br
FROM
(SELECT * FROM #admissionsTable2_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier admipID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID2 = t4.ex_PatientID
WHERE dischargeDate < '2012-04-13'
ALTER TABLE #admissionsTable2_Br DROP COLUMN pID2, ex_PatientID
UPDATE #admissionsTable2_Br SET ageBandAtDischargeDate = 17 WHERE ageBandAtDischargeDate > 17
-- SELECT * FROM #admissionsTable2_Br ORDER BY admipID, dischargeDate

-- ** The next step is to union the two tables.
IF OBJECT_ID ('tempdb..#admissionsTable_Br') IS NOT NULL  
	DROP TABLE #admissionsTable_Br
SELECT DISTINCT * INTO #admissionsTable_Br
FROM
	(
	SELECT newid() AS admiIDkey,
			admipID AS admiPID, 
			admissionDate,
			ageBandAtAdmissionDate,
			admissionMethod,
			NULL AS dischargeDate,
			NULL AS ageBandAtDischargeDate,
			admissionDuration,
			admissionDurationLTHT,
			admissionSource,
			clinicianType,
			dischargeReason,
			admiConsultantSpeciality,
			admiSurvStatus,
			admiSurvTime
			FROM #admissionsTable1_Br
	UNION
	SELECT newid() AS admiIDkey,
			admipID AS admiPID, 
			NULL AS admissionDate,
			NULL AS ageBandAtAdmissionDate,
			admissionMethod,
			dischargeDate,
			ageBandAtDischargeDate,
			admissionDuration,
			admissionDurationLTHT,
			admissionSource,
			clinicianType,
			dischargeReason,
			admiConsultantSpeciality,
			admiSurvStatus,
			admiSurvTime
			FROM #admissionsTable2_Br
	) AS t1
--SELECT * FROM #admissionsTable_Br ORDER BY admiPID, admissionDate, dischargeDate

end --

begin -- ** PPMQuery.leeds.WardStays **
-- ** The first table has wardadmissionDate. **
IF OBJECT_ID ('tempdb..#wardstaysTable1_Br_pre') IS NOT NULL  
	DROP TABLE #wardstaysTable1_Br_pre
CREATE TABLE #wardstaysTable1_Br_pre(
	   pID1 int, 
	   wardadmissionDate date,
	   ageBandAtWardAdmissionDate real,
	   admissionToStayStartDuration real,
	   wardStayDuration real,
	   wardLabel nvarchar(100),
	   wardStartActivityLabel nvarchar(100),
	   wardEndActivityLabel nvarchar(100),
	   wardConsultantSpeciality nvarchar(100),
	   wstaSurvStatus bit,
	   wstaSurvTime real)
INSERT INTO #wardstaysTable1_Br_pre(
	   pID1, 
	   wardadmissionDate,
	   ageBandAtWardAdmissionDate,
	   admissionToStayStartDuration,
	   wardStayDuration,
	   wardLabel,
	   wardStartActivityLabel,
	   wardEndActivityLabel,
	   wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime)
SELECT t1.pID1,
		wardadmissionDate,
		FLOOR(DATEDIFF(DAY,DOB,wardadmissionDate)/(365.4*5)) AS ageBandAtWardAdmissionDate,
		DATEDIFF(DAY, wardadmissionDate, wardStayStartDate) AS admissionToStayStartDuration,
		DATEDIFF(DAY, wardStayStartDate, wardStayEndDate) AS wardStayDuration,
		wardLabel,
		wardStartActivityLabel,
		wardEndActivityLabel,
		wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime
FROM
(SELECT ew_PatientID pID1, 
	   ew_AdmissionDate wardadmissionDate,
	   ew_WardStayStartDate wardStayStartDate,
	   ew_WardStayEndDate wardStayEndDate,
	   ew_WardLabel wardLabel,
	   ew_WardStartActivityLabel wardStartActivityLabel,
	   ew_WardEndActivityLabel wardEndActivityLabel,
	   ew_WardStayContactSpecialityLabel wardConsultantSpeciality,
	   ew_SurvivalStatus wstaSurvStatus,
	   ew_SurvivalTime wstaSurvTime
FROM PPMQuery.leeds.WardStays
WHERE ew_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID1 = t2.pID
ORDER BY pID, wardadmissionDate DESC

IF OBJECT_ID ('tempdb..#wardstaysTable1_Br') IS NOT NULL  
	DROP TABLE #wardstaysTable1_Br
SELECT * INTO #wardstaysTable1_Br
FROM
(SELECT * FROM #wardstaysTable1_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier wstapID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID1 = t4.ex_PatientID
WHERE wardadmissionDate < '2012-04-13'
ALTER TABLE #wardstaysTable1_Br DROP COLUMN pID1, ex_PatientID
UPDATE #wardstaysTable1_Br SET ageBandAtWardAdmissionDate = 17 WHERE ageBandAtWardAdmissionDate > 17
-- SELECT * FROM #wardstaysTable1_Br

-- ** The second table has wardStayStartDate. **
IF OBJECT_ID ('tempdb..#wardstaysTable2_Br_pre') IS NOT NULL  
	DROP TABLE #wardstaysTable2_Br_pre
CREATE TABLE #wardstaysTable2_Br_pre(
	   pID2 int,
	   wardStayStartDate date,
	   ageBandAtWardStartDate real,
	   admissionToStayStartDuration real,
	   wardStayDuration real,
	   wardLabel nvarchar(100),
	   wardStartActivityLabel nvarchar(100),
	   wardEndActivityLabel nvarchar(100),
	   wardConsultantSpeciality nvarchar(100),
	   wstaSurvStatus bit,
	   wstaSurvTime real)
INSERT INTO #wardstaysTable2_Br_pre(
	   pID2,
	   wardStayStartDate,
	   ageBandAtWardStartDate,
	   admissionToStayStartDuration,
	   wardStayDuration,
	   wardLabel,
	   wardStartActivityLabel,
	   wardEndActivityLabel,
	   wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime)
SELECT t1.pID2,
		wardStayStartDate,
		FLOOR(DATEDIFF(DAY,DOB,wardStayStartDate)/(365.4*5)) ageBandAtWardStartDate,
		DATEDIFF(DAY, wardadmissionDate, wardStayStartDate) AS admissionToStayStartDuration,
		DATEDIFF(DAY, wardStayStartDate, wardStayEndDate) AS wardStayDuration,
		wardLabel,
		wardStartActivityLabel,
		wardEndActivityLabel,
		wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime
FROM
(SELECT ew_PatientID pID2,
	   ew_AdmissionDate wardadmissionDate,
	   ew_WardStayStartDate wardStayStartDate,
	   ew_WardStayEndDate wardStayEndDate,
	   ew_WardLabel wardLabel,
	   ew_WardStartActivityLabel wardStartActivityLabel,
	   ew_WardEndActivityLabel wardEndActivityLabel,
	   ew_WardStayContactSpecialityLabel wardConsultantSpeciality,
	   ew_SurvivalStatus wstaSurvStatus,
	   ew_SurvivalTime wstaSurvTime
FROM PPMQuery.leeds.WardStays
WHERE ew_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID, wardStayStartDate DESC

IF OBJECT_ID ('tempdb..#wardstaysTable2_Br') IS NOT NULL  
	DROP TABLE #wardstaysTable2_Br
SELECT * INTO #wardstaysTable2_Br
FROM
(SELECT * FROM #wardstaysTable2_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier wstapID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID2 = t4.ex_PatientID
WHERE wardStayStartDate < '2012-04-13'
ALTER TABLE #wardstaysTable2_Br DROP COLUMN pID2, ex_PatientID
UPDATE #wardstaysTable2_Br SET ageBandAtWardStartDate = 17 WHERE ageBandAtWardStartDate > 17
-- SELECT * FROM #wardstaysTable2_Br

-- ** The third table has wardStayEndDate. **
IF OBJECT_ID ('tempdb..#wardstaysTable3_Br_pre') IS NOT NULL  
	DROP TABLE #wardstaysTable3_Br_pre
CREATE TABLE #wardstaysTable3_Br_pre(
	   pID3 int,
	   wardStayEndDate date,
	   ageBandAtWardEndDate real,
	   admissionToStayStartDuration real,
	   wardStayDuration real,
	   wardLabel nvarchar(100),
	   wardStartActivityLabel nvarchar(100),
	   wardEndActivityLabel nvarchar(100),
	   wardConsultantSpeciality nvarchar(100),
	   wstaSurvStatus bit,
	   wstaSurvTime real)
INSERT INTO #wardstaysTable3_Br_pre(
	   pID3,
	   wardStayEndDate,
	   ageBandAtWardEndDate,
	   admissionToStayStartDuration,
	   wardStayDuration,
	   wardLabel,
	   wardStartActivityLabel,
	   wardEndActivityLabel,
	   wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime)
SELECT t1.pID3,
		wardStayEndDate,
		FLOOR(DATEDIFF(DAY,DOB,wardStayEndDate)/(365.4*5)) ageBandAtWardEndDate,
		DATEDIFF(DAY, wardadmissionDate, wardStayStartDate) AS admissionToStayStartDuration,
		DATEDIFF(DAY, wardStayStartDate, wardStayEndDate) AS wardStayDuration,
		wardLabel,
		wardStartActivityLabel,
		wardEndActivityLabel,
		wardConsultantSpeciality,
	   wstaSurvStatus,
	   wstaSurvTime
FROM
(SELECT ew_PatientID pID3,
	   ew_AdmissionDate wardadmissionDate,
	   ew_WardStayStartDate wardStayStartDate,
	   ew_WardStayEndDate wardStayEndDate,
	   ew_WardLabel wardLabel,
	   ew_WardStartActivityLabel wardStartActivityLabel,
	   ew_WardEndActivityLabel wardEndActivityLabel,
	   ew_WardStayContactSpecialityLabel wardConsultantSpeciality,
	   ew_SurvivalStatus wstaSurvStatus,
	   ew_SurvivalTime wstaSurvTime
FROM PPMQuery.leeds.WardStays
WHERE ew_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID3 = t2.pID
ORDER BY pID, wardStayStartDate DESC

IF OBJECT_ID ('tempdb..#wardstaysTable3_Br') IS NOT NULL  
	DROP TABLE #wardstaysTable3_Br
SELECT * INTO #wardstaysTable3_Br
FROM
(SELECT * FROM #wardstaysTable3_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier wstapID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID3 = t4.ex_PatientID
WHERE wardStayEndDate < '2012-04-13'
ALTER TABLE #wardstaysTable3_Br DROP COLUMN pID3, ex_PatientID
UPDATE #wardstaysTable3_Br SET ageBandAtWardEndDate = 17 WHERE ageBandAtWardEndDate > 17
-- SELECT * FROM #wardstaysTable2_Br

-- ** The next step is to union the two tables.
IF OBJECT_ID ('tempdb..#wardstaysTable_Br') IS NOT NULL  
	DROP TABLE #wardstaysTable_Br
SELECT DISTINCT * INTO #wardstaysTable_Br
FROM
	(
	SELECT newid() AS wstaIDkey,
			wstapID AS wstaPID, 
			wardAdmissionDate,
			ageBandAtWardAdmissionDate,
			NULL AS wardStayStartDate,
			NULL AS ageBandAtWardStartDate,
			NULL AS wardStayEndDate,
			NULL AS ageBandAtWardEndDate,
			admissionToStayStartDuration,
			wardStayDuration,
			wardLabel,
			wardStartActivityLabel,
			wardEndActivityLabel,
			wardConsultantSpeciality,
			wstaSurvStatus,
			wstaSurvTime
			FROM #wardstaysTable1_Br
	UNION
	SELECT newid() AS wstaIDkey,
			wstapID AS wstaPID, 
			NULL AS wardAdmissionDate,
			NULL AS ageBandAtWardAdmissionDate,
			wardStayStartDate,
			ageBandAtWardStartDate,
			NULL AS wardStayEndDate,
			NULL AS ageBandAtWardEndDate,
			admissionToStayStartDuration,
			wardStayDuration,
			wardLabel,
			wardStartActivityLabel,
			wardEndActivityLabel,
			wardConsultantSpeciality,
			wstaSurvStatus,
			wstaSurvTime
			FROM #wardstaysTable2_Br
	UNION
	SELECT newid() AS wstaIDkey,
		wstapID AS wstaPID, 
		NULL AS wardAdmissionDate,
		NULL AS ageBandAtWardAdmissionDate,
		NULL AS wardStayStartDate,
		NULL AS ageBandAtWardStartDate,
		wardStayEndDate,
		ageBandAtWardEndDate,
		admissionToStayStartDuration,
		wardStayDuration,
		wardLabel,
		wardStartActivityLabel,
		wardEndActivityLabel,
		wardConsultantSpeciality,
		wstaSurvStatus,
		wstaSurvTime
		FROM #wardstaysTable3_Br
	) AS t1
--SELECT * FROM #wardstaysTable_Br ORDER BY wstaPID, wardAdmissionDate, wardStayStartDate, wardStayEndDate
end --

begin -- ** PPMQuery.leeds.Radiotherapy **
IF OBJECT_ID ('tempdb..#radioTable_Br_pre') IS NOT NULL  
	DROP TABLE #radioTable_Br_pre
CREATE TABLE #radioTable_Br_pre(
	   radiIDkey uniqueidentifier, pID int, 
	   radioEventDate date,
	   ageBandAtRadioEventDate real,
	   radiActionStatusLabel nvarchar(100),
	   radiSiteLabel nvarchar(100),
	   radiIntentLabel nvarchar(100),
	   radiConsultantSpeciality nvarchar(100),
	   radiSurvStatus bit,
	   radiSurvTime real)
INSERT INTO #radioTable_Br_pre(
	   radiIDkey, pID, 
	   radioEventDate,
	   ageBandAtRadioEventDate,
	   radiActionStatusLabel,
	   radiSiteLabel,
	   radiIntentLabel,
	   radiConsultantSpeciality,
	   radiSurvStatus,
	   radiSurvTime)
SELECT radiIDkey, t1.pID,
		radioEventDate,
		FLOOR(DATEDIFF(DAY,DOB,radioEventDate)/(365.4*5)) ageBandAtRadioEventDate,
		radiActionStatusLabel,
		radiSiteLabel,
		radiIntentLabel,
		radiConsultantSpeciality,
	   radiSurvStatus,
	   radiSurvTime
FROM
(SELECT newid() radiIDkey, er_PatientID pID, 
	   er_EventDate radioEventDate,
	   er_ActionStatusLabel radiActionStatusLabel,
	   er_SiteLabel radiSiteLabel,
	   er_IntentLabel radiIntentLabel,
	   er_ContactSpecialityLabel radiConsultantSpeciality,
	   er_SurvivalStatus radiSurvStatus,
	   er_SurvivalTime radiSurvTime
FROM PPMQuery.leeds.Radiotherapy
WHERE er_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, radioEventDate DESC

IF OBJECT_ID ('tempdb..#radioTable_Br') IS NOT NULL  
	DROP TABLE #radioTable_Br
SELECT * INTO #radioTable_Br
FROM
(SELECT * FROM #radioTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier radipID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE radioEventDate < '2012-04-13'
ALTER TABLE #radioTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #radioTable_Br SET ageBandAtRadioEventDate = 17 WHERE ageBandAtRadioEventDate > 17
--SELECT * FROM #radioTable_Br
end --

begin -- ** PPMQuery.leeds.RadiotherapyEx **
-- ** This first table has radioStartDate. **
IF OBJECT_ID ('tempdb..#radioExTable1_Br_pre') IS NOT NULL  
	DROP TABLE #radioExTable1_Br_pre
CREATE TABLE #radioExTable1_Br_pre(
	   radxIDkey uniqueidentifier, pID1 int,
	   radioStartDate date,
	   ageBandAtRadioStartDate real,
	   radioDuration real,
	   radioTypeLabel nvarchar(100))
INSERT INTO #radioExTable1_Br_pre(
	   radxIDkey, pID1,
	   radioStartDate,
	   ageBandAtRadioStartDate,
	   radioDuration,
	   radioTypeLabel)
SELECT radxIDkey, t1.pID1,
		radioStartDate,
		FLOOR(DATEDIFF(DAY,DOB,radioStartDate)/(365.4*5)) ageBandAtRadioStartDate,
		DATEDIFF(DAY, radioStartDate, radioEndDate) AS radioDuration,
		radioTypeLabel
FROM
(SELECT newid() radxIDkey, er_PatientID pID1,
		er_RadiotherapyStartDate radioStartDate,
		er_RadiotherapyEndDate radioEndDate,
		er_TypeCode_CodeLabel radioTypeLabel
FROM PPMQuery.leeds.RadiotherapyEx
WHERE er_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID1 = t2.pID
ORDER BY pID, radioStartDate DESC

IF OBJECT_ID ('tempdb..#radioExTable1_Br') IS NOT NULL  
	DROP TABLE #radioExTable1_Br
SELECT * INTO #radioExTable1_Br
FROM
(SELECT * FROM #radioExTable1_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier radxpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID1 = t4.ex_PatientID
WHERE radioStartDate < '2012-04-13'
ALTER TABLE #radioExTable1_Br DROP COLUMN pID1, ex_PatientID
UPDATE #radioExTable1_Br SET ageBandAtRadioStartDate = 17 WHERE ageBandAtRadioStartDate > 17
-- SELECT * FROM #radioExTable1_Br

-- ** This second table has radioEndDate. **
IF OBJECT_ID ('tempdb..#radioExTable2_Br_pre') IS NOT NULL  
	DROP TABLE #radioExTable2_Br_pre
CREATE TABLE #radioExTable2_Br_pre(
	   radxIDkey uniqueidentifier, pID2 int,
	   radioEndDate date,
	   ageBandAtRadioEndDate real,
	   radioDuration real,
	   radioTypeLabel nvarchar(100))
INSERT INTO #radioExTable2_Br_pre(
	   radxIDkey, pID2,
	   radioEndDate,
	   ageBandAtRadioEndDate,
	   radioDuration,
	   radioTypeLabel)
SELECT radxIDkey, t1.pID2,
		radioEndDate,
		FLOOR(DATEDIFF(DAY,DOB,radioEndDate)/(365.4*5)) ageBandAtRadioEndDate,
		DATEDIFF(DAY, radioStartDate, radioEndDate) AS radioDuration,
		radioTypeLabel
FROM
(SELECT newid() radxIDkey, er_PatientID pID2,
		er_RadiotherapyStartDate radioStartDate,
		er_RadiotherapyEndDate radioEndDate,
		er_TypeCode_CodeLabel radioTypeLabel
FROM PPMQuery.leeds.RadiotherapyEx
WHERE er_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID, radioEndDate DESC

IF OBJECT_ID ('tempdb..#radioExTable2_Br') IS NOT NULL
	DROP TABLE #radioExTable2_Br
SELECT * INTO #radioExTable2_Br
FROM
(SELECT * FROM #radioExTable2_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier radxpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID2 = t4.ex_PatientID
WHERE radioEndDate < '2012-04-13'
ALTER TABLE #radioExTable2_Br DROP COLUMN pID2, ex_PatientID
UPDATE #radioExTable2_Br SET ageBandAtRadioEndDate = 17 WHERE ageBandAtRadioEndDate > 17
-- SELECT * FROM #radioExTable2_Br

-- ** The next step is to union the two tables.
IF OBJECT_ID ('tempdb..#radioExTable_Br') IS NOT NULL
	DROP TABLE #radioExTable_Br
SELECT DISTINCT * INTO #radioExTable_Br
FROM
	(
	SELECT newid() AS radxIDkey,
			radxpID AS radxPID,
			radioStartDate,
			ageBandAtRadioStartDate,
			NULL AS radioEndDate,
			NULL AS ageBandAtRadioEndDate,
			radioDuration,
			radioTypeLabel
			FROM #radioExTable1_Br
	UNION
	SELECT newid() AS radxIDkey,
			radxpID AS radxPID, 
			NULL AS radioStartDate,
			NULL AS ageBandAtRadioStartDate,
			radioEndDate,
			ageBandAtRadioEndDate,
			radioDuration,
			radioTypeLabel
			FROM #radioExTable2_Br
	) AS t1
--SELECT * FROM #radioExTable_Br ORDER BY radxPID
end --

begin -- ** Chemotherapy **
-- ******* This is all a bit complicated because the data is all over the place.
 -- ** PPMQuery.leeds.ChemoDrugs **
 -- ** This first table has the dated chemoDrugs data - cycleStartDate. **
IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_time1_pre') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_time1_pre
CREATE TABLE #chemoDrugsTable_Br_chemD_time1_pre(
		pID1 int,
		regimenID1 int,
		cycleNum1 int,
		cycleStartDate date,
		ageBandAtCycleStartDate real)
INSERT INTO #chemoDrugsTable_Br_chemD_time1_pre(
		pID1,
		regimenID1,
		cycleNum1,
		cycleStartDate,
		ageBandAtCycleStartDate)
SELECT t1.pID1,
		regimenID1,
		cycleNum1,
		cycleStartDate,
		FLOOR(DATEDIFF(DAY,DOB,cycleStartDate)/(365.4*5)) ageBandAtCycleStartDate
FROM
(SELECT ecd_PatientID pID1,
		ecd_RegimenID regimenID1,
		ecd_CycleNumber cycleNum1,
		ecd_CycleStartDate cycleStartDate
FROM PPMQuery.leeds.ChemoDrugs
WHERE ecd_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID1 = t2.pID
ORDER BY pID, cycleStartDate DESC

IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_time1') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_time1
SELECT * INTO #chemoDrugsTable_Br_chemD_time1
FROM
(SELECT * FROM #chemoDrugsTable_Br_chemD_time1_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID1, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID1 = t2.ex_PatientID
WHERE cycleStartDate < '2012-04-13'
ALTER TABLE #chemoDrugsTable_Br_chemD_time1 DROP COLUMN pID1, ex_PatientID
UPDATE #chemoDrugsTable_Br_chemD_time1 SET ageBandAtCycleStartDate = 17 WHERE ageBandAtCycleStartDate > 17
--SELECT * FROM #chemoDrugsTable_Br_chemD_time1 ORDER BY chemPID1, regimenID1, cycleNum1, cycleStartDate
-- ** This second table has the dated chemoDrugs data - drugStartDate. **
IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_time2_pre') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_time2_pre
CREATE TABLE #chemoDrugsTable_Br_chemD_time2_pre(
		pID2 int,
		regimenID2 int,
		cycleNum2 int,
		drugStartDate date,
		ageBandAtDrugStartDate real)
INSERT INTO #chemoDrugsTable_Br_chemD_time2_pre(
		pID2,
		regimenID2,
		cycleNum2,
		drugStartDate,
		ageBandAtDrugStartDate)
SELECT t1.pID2,
		regimenID2,
		cycleNum2,
		drugStartDate,
		FLOOR(DATEDIFF(DAY,DOB,drugStartDate)/(365.4*5)) ageBandAtDrugStartDate
FROM
(SELECT ecd_PatientID pID2,
		ecd_RegimenID regimenID2,
		ecd_CycleNumber cycleNum2,
		ecd_DrugStartDate drugStartDate
FROM PPMQuery.leeds.ChemoDrugs
WHERE ecd_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID, drugStartDate DESC

IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_time2') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_time2	
SELECT * INTO #chemoDrugsTable_Br_chemD_time2
FROM
(SELECT * FROM #chemoDrugsTable_Br_chemD_time2_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID2, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID2 = t2.ex_PatientID
WHERE drugStartDate < '2012-04-13'
ALTER TABLE #chemoDrugsTable_Br_chemD_time2 DROP COLUMN pID2, ex_PatientID
UPDATE #chemoDrugsTable_Br_chemD_time2 SET ageBandAtDrugStartDate = 17 WHERE ageBandAtDrugStartDate > 17
--SELECT * FROM #chemoDrugsTable_Br_chemD_time2 ORDER BY chemPID2, regimenID2, cycleNum2, drugStartDate
-- ** This third table has the non-dated chemoDrugs data. ** 
IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_notime_pre') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_notime_pre
CREATE TABLE #chemoDrugsTable_Br_chemD_notime_pre(
		pID3 int,
		heightValue real,
		weightValue real,
		regimenID3 int,
		regimenIntentLabel nvarchar(100),
		regimenDrugLabel nvarchar(100),
		regimenDuration nvarchar(10),
		cycleNum3 int,
		drugLabel nvarchar(100),
		drugDeliveryRouteLabel nvarchar(20),
		drugReqDose real,
		drugDose real,
		drugFreq nvarchar(10),
		drugConsultantSpeciality_drug nvarchar(100),
	   chemSurvStatus bit,
	   chemSurvTime real)
INSERT INTO #chemoDrugsTable_Br_chemD_notime_pre(
		pID3,
		heightValue,
		weightValue,
		regimenID3,
		regimenIntentLabel,
		regimenDrugLabel,
		regimenDuration,
		cycleNum3,
		drugLabel,
		drugDeliveryRouteLabel,
		drugReqDose,
		drugDose,
		drugFreq,
		drugConsultantSpeciality_drug,
	   chemSurvStatus,
	   chemSurvTime)
SELECT t1.pID3,
		heightValue,
		weightValue,
		regimenID3,
		regimenIntentLabel,
		regimenDrugLabel,
		regimenDuration,
		cycleNum3,
		drugLabel,
		drugDeliveryRouteLabel,
		drugReqDose,
		drugDose,
		drugFreq,
		drugConsultantSpeciality_drug,
	   chemSurvStatus,
	   chemSurvTime
FROM
(SELECT ecd_PatientID pID3,		
		ecc_Height heightValue,
		ecc_Weight weightValue,
		ecd_RegimenID regimenID3,
		ecd_RegimenIntentCodeLabel regimenIntentLabel,
		ecd_RegimenLabel regimenDrugLabel,
		ecd_Duration regimenDuration,
		ecd_CycleNumber cycleNum3,
		ecd_DrugLabel drugLabel,
		ecd_AdministrationRoute drugDeliveryRouteLabel,
		ecd_ReqDose drugReqDose,
		ecd_DrugDose drugDose,
		ecd_Freq drugFreq,
		ecd_DrugContactSpecialityLabel drugConsultantSpeciality_drug,
	   ecd_SurvivalStatus chemSurvStatus,
	   ecd_SurvivalTime chemSurvTime
FROM PPMQuery.leeds.ChemoDrugs
WHERE ecd_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID3 = t2.pID
ORDER BY pID, regimenID3, cycleNum3 DESC

IF OBJECT_ID ('tempdb..#chemoDrugsTable_Br_chemD_notime') IS NOT NULL
	DROP TABLE #chemoDrugsTable_Br_chemD_notime
SELECT * INTO #chemoDrugsTable_Br_chemD_notime
FROM
(SELECT * FROM #chemoDrugsTable_Br_chemD_notime_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID3, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID3 = t2.ex_PatientID
ALTER TABLE #chemoDrugsTable_Br_chemD_notime DROP COLUMN pID3, ex_PatientID
--SELECT * FROM #chemoDrugsTable_Br_chemD_notime ORDER BY chemPID3, regimenID3, cycleNum3


-- ** PPMQuery.leeds.ChemoCycles **
-- ** This fourth table has the non-dated chemoCycles data. There is no dated information** 
IF OBJECT_ID ('tempdb..#chemoCycleTable_Br_notime_pre') IS NOT NULL
	DROP TABLE #chemoCycleTable_Br_notime_pre
CREATE TABLE #chemoCycleTable_Br_notime_pre(
		pID4 int,
		regimenID4 int,
		cycleNum4 int,
		cycleActionStatus nvarchar(100),
		regOutcome nvarchar(100),
		regLabel nvarchar(100),
		expDurationOfCycle int)
INSERT INTO #chemoCycleTable_Br_notime_pre(
		pID4,
		regimenID4,
		cycleNum4,
		cycleActionStatus,
		regOutcome,
		regLabel,
		expDurationOfCycle)
SELECT t1.pID4,
		regimenID4,
		cycleNum4,
		cycleActionStatus,
		regOutcome,
		regLabel,
		expDurationOfCycle
FROM
(SELECT ecc_PatientID pID4,		
		ecc_RegimenID regimenID4,
		ecc_CycleNumber cycleNum4,
		ecc_CycleActionStatusLabel cycleActionStatus,
		ecc_RegimenOutcomeLabel regOutcome,
		ecc_RegimenLabel regLabel,
		ecc_MaxDays expDurationOfCycle
FROM PPMQuery.leeds.ChemoCycles
WHERE ecc_PatientID IN (SELECT * FROM #breastPatients)
	AND ecc_RegimenLabel NOT LIKE '%OPMAS%' -- This comes from MT. He said OPMAS is and
											-- old system and does not have reliable 
											-- reliable information.
	) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID4 = t2.pID
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#chemoCycleTable_Br_notime') IS NOT NULL
	DROP TABLE #chemoCycleTable_Br_notime
SELECT * INTO #chemoCycleTable_Br_notime
FROM
(SELECT * FROM #chemoCycleTable_Br_notime_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID4, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID4 = t2.ex_PatientID
ALTER TABLE #chemoCycleTable_Br_notime DROP COLUMN pID4, ex_PatientID
--SELECT * FROM #chemoCycleTable_Br_notime ORDER BY chemPID4, regimenID4, cycleNum4


-- ** PPMQuery.leeds.ChemoRegimens **
-- ** This fifth table has the dated chemoRegimens data - regStartDate. **
IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time1_pre') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time1_pre
CREATE TABLE #chemoRegimenTable_Br_chemR_time1_pre(
		pID5 int,
		regimenID5 int,
		regStartDate date,
		ageBandAtRegStartDate real)
INSERT INTO #chemoRegimenTable_Br_chemR_time1_pre(
		pID5,
		regimenID5,
		regStartDate,
		ageBandAtRegStartDate)
SELECT t1.pID5,
		regimenID5,
		regStartDate,
		FLOOR(DATEDIFF(DAY,DOB,regStartDate)/(365.4*5)) ageBandAtRegStartDate
FROM
(SELECT ec_PatientID pID5,		
		ec_EventID regimenID5,
		ec_RegimenStartDate regStartDate
FROM PPMQuery.leeds.ChemoRegimens
WHERE ec_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID5 = t2.pID
ORDER BY pID, regStartDate DESC

IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time1') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time1
SELECT * INTO #chemoRegimenTable_Br_chemR_time1
FROM
(SELECT * FROM #chemoRegimenTable_Br_chemR_time1_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID5, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID5 = t2.ex_PatientID
WHERE regStartDate < '2012-04-13'
ALTER TABLE #chemoRegimenTable_Br_chemR_time1 DROP COLUMN pID5, ex_PatientID
UPDATE #chemoRegimenTable_Br_chemR_time1 SET ageBandAtRegStartDate = 17 WHERE ageBandAtRegStartDate > 17
--SELECT * FROM #chemoRegimenTable_Br_chemR_time1 ORDER BY chemPID5, regimenID5, regStartDate
-- ** This sixth table has the dated chemoRegimens data - regEndDate. **
IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time2_pre') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time2_pre
CREATE TABLE #chemoRegimenTable_Br_chemR_time2_pre(
		pID6 int,
		regimenID6 int,
		regEndDate date,
		ageBandAtRegEndDate real)
INSERT INTO #chemoRegimenTable_Br_chemR_time2_pre(
		pID6,
		regimenID6,
		regEndDate,
		ageBandAtRegEndDate)
SELECT t1.pID6,
		regimenID6,
		regEndDate,
		FLOOR(DATEDIFF(DAY,DOB,regEndDate)/(365.4*5)) ageBandAtRegEndDate
FROM
(SELECT ec_PatientID pID6,		
		ec_EventID regimenID6,
		ec_RegimenEndDate regEndDate
FROM PPMQuery.leeds.ChemoRegimens
WHERE ec_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID6 = t2.pID
ORDER BY pID, regEndDate DESC

IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time2') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time2
SELECT * INTO #chemoRegimenTable_Br_chemR_time2
FROM
(SELECT * FROM #chemoRegimenTable_Br_chemR_time2_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID6, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID6 = t2.ex_PatientID
WHERE regEndDate < '2012-04-13'
ALTER TABLE #chemoRegimenTable_Br_chemR_time2 DROP COLUMN pID6, ex_PatientID
UPDATE #chemoRegimenTable_Br_chemR_time2 SET ageBandAtRegEndDate = 17 WHERE ageBandAtRegEndDate > 17
--SELECT * FROM #chemoRegimenTable_Br_chemR_time2 ORDER BY chemPID6, regimenID6, regEndDate 
-- ** This seventh table has the dated chemoRegimens data - regDecisionDate. **
IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time3_pre') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time3_pre
CREATE TABLE #chemoRegimenTable_Br_chemR_time3_pre(
		pID7 int,
		regimenID7 int,
		regDecisionDate date,
		ageBandAtRegDecisionDate real)
INSERT INTO #chemoRegimenTable_Br_chemR_time3_pre(
		pID7,
		regimenID7,
		regDecisionDate,
		ageBandAtRegDecisionDate)
SELECT t1.pID7,
		regimenID7,
		regDecisionDate,
		FLOOR(DATEDIFF(DAY,DOB,regDecisionDate)/(365.4*5)) ageBandAtRegDecisionDate
FROM
(SELECT ec_PatientID pID7,		
		ec_EventID regimenID7,
		ec_DecisionDate regDecisionDate
FROM PPMQuery.leeds.ChemoRegimens
WHERE ec_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID7 = t2.pID
ORDER BY pID, regDecisionDate DESC

IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_time3') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_time3
SELECT * INTO #chemoRegimenTable_Br_chemR_time3
FROM
(SELECT * FROM #chemoRegimenTable_Br_chemR_time3_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID7, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID7 = t2.ex_PatientID
WHERE regDecisionDate < '2012-04-13'
ALTER TABLE #chemoRegimenTable_Br_chemR_time3 DROP COLUMN pID7, ex_PatientID
UPDATE #chemoRegimenTable_Br_chemR_time3 SET ageBandAtRegDecisionDate = 17 WHERE ageBandAtRegDecisionDate > 17
--SELECT * FROM #chemoRegimenTable_Br_chemR_time3 ORDER BY chemPID7, regimenID7, regDecisionDate
-- ** This eight table has the non-dated chemoRegimen data. There is no dated information** 
IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_notime_pre') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_notime_pre
CREATE TABLE #chemoRegimenTable_Br_chemR_notime_pre(
		pID8 int,
		regimenID8 int,
		drugTherapyType nvarchar(50),
		stoppingReason nvarchar(50),
		trialYesNo bit)
INSERT INTO #chemoRegimenTable_Br_chemR_notime_pre(
		pID8,
		regimenID8,
		drugTherapyType,
		stoppingReason,
		trialYesNo)
SELECT t1.pID8,
		regimenID8,
		drugTherapyType,
		stoppingReason,
		trialYesNo
FROM
(SELECT ec_PatientID pID8,		
		ec_EventID regimenID8,
		ec_DrugTherapyTypeLabel drugTherapyType,
		ec_StoppingReasonLabel stoppingReason,
		ec_ClinicalTrialYesNo trialYesNo
FROM PPMQuery.leeds.ChemoRegimens
WHERE ec_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID8 = t2.pID
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#chemoRegimenTable_Br_chemR_notime') IS NOT NULL
	DROP TABLE #chemoRegimenTable_Br_chemR_notime
SELECT * INTO #chemoRegimenTable_Br_chemR_notime
FROM
(SELECT * FROM #chemoRegimenTable_Br_chemR_notime_pre) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier chemPID8, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t2
ON t1.pID8 = t2.ex_PatientID
ALTER TABLE #chemoRegimenTable_Br_chemR_notime DROP COLUMN pID8, ex_PatientID
--SELECT * FROM #chemoRegimenTable_Br_chemR_notime ORDER BY chemPID8, regimenID8


-- ** The next step is to join the non-dated data from all chemotherapy tables to  
-- ** each of the dated tables.
--
-- ** #chemoDrugsTable_Br_chemD_time1 to become #chemoTable1_Br
IF OBJECT_ID ('tempdb..#chemoTable1_Br') IS NOT NULL
	DROP TABLE #chemoTable1_Br
SELECT DISTINCT * INTO #chemoTable1_Br
FROM
	(
	SELECT chemPID1 AS chemPID,
			regimenID1 AS regimenID,
			cycleNum1 AS cycleNum,
			* FROM #chemoDrugsTable_Br_chemD_time1
	) AS t1
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoDrugsTable_Br_chemD_notime
	) AS t2
ON t1.chemPID1 = t2.chemPID3
	AND t1.regimenID1 = t2.regimenID3
	AND t1.cycleNum1 = t2.cycleNum3
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoCycleTable_Br_notime
	) AS t3
ON t1.chemPID1 = t3.chemPID4
	AND t1.regimenID1 = t3.regimenID4
	AND t1.cycleNum1 = t3.cycleNum4
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoRegimenTable_Br_chemR_notime
	) AS t4
ON t1.chemPID1 = t4.chemPID8
	AND t1.regimenID1 = t4.regimenID8
ALTER TABLE #chemoTable1_Br DROP COLUMN chemPID1, chemPID3, chemPID4, chemPID8,
										regimenID1, regimenID3, regimenID4, regimenID8,
										cycleNum1, cycleNum3, cycleNum4							
-- ** #chemoDrugsTable_Br_chemD_time2 to become #chemoTable2_Br
IF OBJECT_ID ('tempdb..#chemoTable2_Br') IS NOT NULL
	DROP TABLE #chemoTable2_Br
SELECT DISTINCT * INTO #chemoTable2_Br
FROM
	(
	SELECT chemPID2 AS chemPID,
			regimenID2 AS regimenID,
			cycleNum2 AS cycleNum,
			* FROM #chemoDrugsTable_Br_chemD_time2
	) AS t1
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoDrugsTable_Br_chemD_notime
	) AS t2
ON t1.chemPID2 = t2.chemPID3
	AND t1.regimenID2 = t2.regimenID3
	AND t1.cycleNum2 = t2.cycleNum3
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoCycleTable_Br_notime
	) AS t3
ON t1.chemPID2 = t3.chemPID4
	AND t1.regimenID2 = t3.regimenID4
	AND t1.cycleNum2 = t3.cycleNum4
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoRegimenTable_Br_chemR_notime
	) AS t4
ON t1.chemPID2 = t4.chemPID8
	AND t1.regimenID2 = t4.regimenID8
ALTER TABLE #chemoTable2_Br DROP COLUMN chemPID2, chemPID3, chemPID4, chemPID8,
										regimenID2, regimenID3, regimenID4, regimenID8,
										cycleNum2, cycleNum3, cycleNum4
-- ** #chemoRegimenTable_Br_chemR_time1 to become #chemoTable3_Br
IF OBJECT_ID ('tempdb..#chemoTable3_Br') IS NOT NULL
	DROP TABLE #chemoTable3_Br
SELECT DISTINCT * INTO #chemoTable3_Br
FROM
	(
	SELECT chemPID5 AS chemPID,
			regimenID5 AS regimenID,
			* FROM #chemoRegimenTable_Br_chemR_time1
	) AS t1
LEFT OUTER JOIN
	(
	SELECT cycleNum3 AS cycleNUM, * FROM #chemoDrugsTable_Br_chemD_notime
	) AS t2
ON t1.chemPID5 = t2.chemPID3
	AND t1.regimenID5 = t2.regimenID3
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoCycleTable_Br_notime
	) AS t3
ON t1.chemPID5 = t3.chemPID4
	AND t1.regimenID5 = t3.regimenID4
	AND t2.cycleNum3 = t3.cycleNum4
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoRegimenTable_Br_chemR_notime
	) AS t4
ON t1.chemPID5 = t4.chemPID8
	AND t1.regimenID5 = t4.regimenID8
ORDER BY chemPID, regimenID3, cycleNum3, regStartDate
ALTER TABLE #chemoTable3_Br DROP COLUMN chemPID5, chemPID3, chemPID4, chemPID8,
										regimenID5, regimenID3, regimenID4, regimenID8,
										cycleNum3, cycleNum4
-- ** #chemoRegimenTable_Br_chemR_time2 to become #chemoTable4_Br
IF OBJECT_ID ('tempdb..#chemoTable4_Br') IS NOT NULL
	DROP TABLE #chemoTable4_Br
SELECT DISTINCT * INTO #chemoTable4_Br
FROM
	(
	SELECT chemPID6 AS chemPID,
			regimenID6 AS regimenID,
			* FROM #chemoRegimenTable_Br_chemR_time2
	) AS t1
LEFT OUTER JOIN
	(
	SELECT cycleNum3 AS cycleNUM, * FROM #chemoDrugsTable_Br_chemD_notime
	) AS t2
ON t1.chemPID6 = t2.chemPID3
	AND t1.regimenID6 = t2.regimenID3
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoCycleTable_Br_notime
	) AS t3
ON t1.chemPID6 = t3.chemPID4
	AND t1.regimenID6 = t3.regimenID4
	AND t2.cycleNum3 = t3.cycleNum4
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoRegimenTable_Br_chemR_notime
	) AS t4
ON t1.chemPID6 = t4.chemPID8
	AND t1.regimenID6 = t4.regimenID8
ORDER BY chemPID, regimenID3, cycleNum3, regEndDate
ALTER TABLE #chemoTable4_Br DROP COLUMN chemPID6, chemPID3, chemPID4, chemPID8,
										regimenID6, regimenID3, regimenID4, regimenID8,
										cycleNum3, cycleNum4
-- ** #chemoRegimenTable_Br_chemR_time3 to become #chemoTable5_Br
IF OBJECT_ID ('tempdb..#chemoTable5_Br') IS NOT NULL
	DROP TABLE #chemoTable5_Br
SELECT DISTINCT * INTO #chemoTable5_Br
FROM
	(
	SELECT chemPID7 AS chemPID,
			regimenID7 AS regimenID,
			* FROM #chemoRegimenTable_Br_chemR_time3
	) AS t1
LEFT OUTER JOIN
	(
	SELECT cycleNum3 AS cycleNUM, * FROM #chemoDrugsTable_Br_chemD_notime
	) AS t2
ON t1.chemPID7 = t2.chemPID3
	AND t1.regimenID7 = t2.regimenID3
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoCycleTable_Br_notime
	) AS t3
ON t1.chemPID7 = t3.chemPID4
	AND t1.regimenID7 = t3.regimenID4
	AND t2.cycleNum3 = t3.cycleNum4
LEFT OUTER JOIN
	(
	SELECT * FROM #chemoRegimenTable_Br_chemR_notime
	) AS t4
ON t1.chemPID7 = t4.chemPID8
	AND t1.regimenID7 = t4.regimenID8
ORDER BY chemPID, regimenID3, cycleNum3, regDecisionDate
ALTER TABLE #chemoTable5_Br DROP COLUMN chemPID7, chemPID3, chemPID4, chemPID8,
										regimenID7, regimenID3, regimenID4, regimenID8,
										cycleNum3, cycleNum4

-- ** The final step is to union everything.
--
IF OBJECT_ID ('tempdb..#chemoTable_Br') IS NOT NULL
	DROP TABLE #chemoTable_Br
SELECT DISTINCT * INTO #chemoTable_Br
FROM
	(
	SELECT newid() AS chemIDkey,
			chempID AS chemPID,
			regimenID,
			cycleNum,
			cycleStartDate,
			ageBandAtCycleStartDate,
			NULL AS drugStartDate,
			NULL AS ageBandAtDrugStartDate,
			NULL AS regStartDate,
			NULL AS ageBandAtRegStartDate,
			NULL AS regEndDate,
			NULL AS ageBandAtRegEndDate,
			NULL AS regDecisionDate,
			NULL AS ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			drugConsultantSpeciality_drug,
			chemSurvStatus,
			chemSurvTime,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo
			FROM #chemoTable1_Br
	UNION
	SELECT newid() AS chemIDkey,
			chempID AS chemPID, 
			regimenID,
			cycleNum,
			NULL AS cycleStartDate,
			NULL AS ageBandAtCycleStartDate,
			drugStartDate,
			ageBandAtDrugStartDate,
			NULL AS regStartDate,
			NULL AS ageBandAtRegStartDate,
			NULL AS regEndDate,
			NULL AS ageBandAtRegEndDate,
			NULL AS regDecisionDate,
			NULL AS ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			drugConsultantSpeciality_drug,
			chemSurvStatus,
			chemSurvTime,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo
			FROM #chemoTable2_Br
	UNION
	SELECT newid() AS chemIDkey,
			chempID AS chemPID, 
			regimenID,
			cycleNum,
			NULL AS cycleStartDate,
			NULL AS ageBandAtCycleStartDate,
			NULL AS drugStartDate,
			NULL AS ageBandAtDrugStartDate,
			regStartDate,
			ageBandAtRegStartDate,
			NULL AS regEndDate,
			NULL AS ageBandAtRegEndDate,
			NULL AS regDecisionDate,
			NULL AS ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			drugConsultantSpeciality_drug,
			chemSurvStatus,
			chemSurvTime,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo
			FROM #chemoTable3_Br
	UNION
	SELECT newid() AS chemIDkey,
			chempID AS chemPID, 
			regimenID,
			cycleNum,
			NULL AS cycleStartDate,
			NULL AS ageBandAtCycleStartDate,
			NULL AS drugStartDate,
			NULL AS ageBandAtDrugStartDate,
			NULL AS regStartDate,
			NULL AS ageBandAtRegStartDate,
			regEndDate,
			ageBandAtRegEndDate,
			NULL AS regDecisionDate,
			NULL AS ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			drugConsultantSpeciality_drug,
			chemSurvStatus,
			chemSurvTime,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo
			FROM #chemoTable4_Br
	UNION
	SELECT newid() AS chemIDkey,
			chempID AS chemPID, 
			regimenID,
			cycleNum,
			NULL AS cycleStartDate,
			NULL AS ageBandAtCycleStartDate,
			NULL AS drugStartDate,
			NULL AS ageBandAtDrugStartDate,
			NULL AS regStartDate,
			NULL AS ageBandAtRegStartDate,
			NULL AS regEndDate,
			NULL AS ageBandAtRegEndDate,
			regDecisionDate,
			ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			drugConsultantSpeciality_drug,
			chemSurvStatus,
			chemSurvTime,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo
			FROM #chemoTable5_Br
	) AS t1
--SELECT * FROM #chemoTable_Br ORDER BY chemPID, regimenID, cycleNum, regStartDate, cycleStartDate, drugStartDate, regEndDate, regDecisionDate

end

begin -- ** PPMQuery.leeds.Surgery & PPMQuery.leeds.Pathology **
-- ** Start with the Surgery stuff.
IF OBJECT_ID ('tempdb..#surgeryTable_Br_time_pre') IS NOT NULL  
	DROP TABLE #surgeryTable_Br_time_pre
CREATE TABLE #surgeryTable_Br_time_pre(
		pID1 int,
		surgID1 int,
		surgeryDate date,
		ageBandAtSurgeryDate real)
INSERT INTO #surgeryTable_Br_time_pre(
		pID1,
		surgID1,
		surgeryDate,
		ageBandAtSurgeryDate)
SELECT t1.pID1,
		surgID1,
		surgeryDate,
		FLOOR(DATEDIFF(DAY,DOB,surgeryDate)/(365.4*5)) ageBandAtSurgeryDate
FROM
(SELECT es_PatientID pID1,
		es_EventID surgID1,
		es_SurgeryDate surgeryDate
FROM PPMQuery.leeds.Surgery
WHERE es_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID1 = t2.pID
ORDER BY pID, surgeryDate DESC

IF OBJECT_ID ('tempdb..#surgeryTable_Br_time') IS NOT NULL
	DROP TABLE #surgeryTable_Br_time
SELECT * INTO #surgeryTable_Br_time
FROM
(SELECT * FROM #surgeryTable_Br_time_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier surgpID1, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID1 = t4.ex_PatientID
WHERE surgeryDate < '2012-04-13'
ALTER TABLE #surgeryTable_Br_time DROP COLUMN pID1, ex_PatientID
UPDATE #surgeryTable_Br_time SET ageBandAtSurgeryDate = 17 WHERE ageBandAtSurgeryDate > 17
--SELECT * FROM #surgeryTable_Br_time

IF OBJECT_ID ('tempdb..#surgeryTable_Br_notime_pre') IS NOT NULL
	DROP TABLE #surgeryTable_Br_notime_pre
CREATE TABLE #surgeryTable_Br_notime_pre(
		pID2 int,
		surgID2 int,
		surgActionStatusLabel nvarchar(100),
		surgIntent nvarchar(100),
		operationReason nvarchar(150),
		procedureLabel nvarchar(300),
		outcomeLabel nvarchar(100),
		residualDisease nvarchar(100),
		surgConsultantSpeciality nvarchar(100),
	   surgSurvStatus bit,
	   surgSurvTime real)
INSERT INTO #surgeryTable_Br_notime_pre(
		pID2,
		surgID2,
		surgActionStatusLabel,
		surgIntent,
		operationReason,
		procedureLabel,
		outcomeLabel,
		residualDisease,
		surgConsultantSpeciality,
	   surgSurvStatus,
	   surgSurvTime)
SELECT t1.pID2,
		surgID2,
		surgActionStatusLabel,
		surgIntent,
		operationReason,
		procedureLabel,
		outcomeLabel,
		residualDisease,
		surgConsultantSpeciality,
	   surgSurvStatus,
	   surgSurvTime
FROM
(SELECT es_PatientID pID2,
		es_EventID surgID2,
		es_ActionStatusLabel surgActionStatusLabel,
		es_OperationReason operationReason,
		es_PurposeCodeLabel surgIntent,
		es_MainProcedureLabel procedureLabel,
		es_OutcomeLabel outcomeLabel,
		es_ResidualDiseaseLabel residualDisease,
		es_ConsContactSpecialityLabel surgConsultantSpeciality,
	   es_SurvivalStatus surgSurvStatus,
	   es_SurvivalTime surgSurvTime
FROM PPMQuery.leeds.Surgery
WHERE es_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#surgeryTable_Br_notime') IS NOT NULL
	DROP TABLE #surgeryTable_Br_notime
SELECT * INTO #surgeryTable_Br_notime
FROM
(SELECT * FROM #surgeryTable_Br_notime_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier surgpID2, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID2 = t4.ex_PatientID
ALTER TABLE #surgeryTable_Br_notime DROP COLUMN pID2, ex_PatientID
--SELECT * FROM #surgeryTable_Br_notime
 
 
-- ** Now get the Pathology stuff.
IF OBJECT_ID ('tempdb..#pathologyTable_Br_time_pre') IS NOT NULL
	DROP TABLE #pathologyTable_Br_time_pre
CREATE TABLE #pathologyTable_Br_time_pre(
		pID3 int,
		pathDate date,
		ageBandAtPathDate real,
		surgID3 int)
INSERT INTO #pathologyTable_Br_time_pre(
		pID3,
		pathDate,
		ageBandAtPathDate,
		surgID3)
SELECT t1.pID3,
		pathDate,
		FLOOR(DATEDIFF(DAY,DOB,pathDate)/(365.4*5)) ageBandAtPathDate,
		surgID3
FROM
(SELECT esp_PatientID pID3,
		esp_PathologyDate pathDate,
		esp_SurgeryID surgID3
FROM PPMQuery.leeds.Pathology
WHERE esp_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID3 = t2.pID
ORDER BY pID, pathDate DESC

IF OBJECT_ID ('tempdb..#pathologyTable_Br_time') IS NOT NULL
	DROP TABLE #pathologyTable_Br_time
SELECT * INTO #pathologyTable_Br_time
FROM
(SELECT * FROM #pathologyTable_Br_time_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier pathpID1, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID3 = t4.ex_PatientID
WHERE pathDate < '2012-04-13'
ALTER TABLE #pathologyTable_Br_time DROP COLUMN pID3, ex_PatientID
UPDATE #pathologyTable_Br_time SET ageBandAtPathDate = 17 WHERE ageBandAtPathDate > 17
 --SELECT * FROM #pathologyTable_Br_time 

IF OBJECT_ID ('tempdb..#pathologyTable_Br_notime_pre') IS NOT NULL
	DROP TABLE #pathologyTable_Br_notime_pre
CREATE TABLE #pathologyTable_Br_notime_pre(
		pID4 int,
		surgID4 int,
		pathSpecimenLabel nvarchar(100),
		pathSite nvarchar(100),
		pathMorphLabel nvarchar(100),
		pathMorphCDS nvarchar(100),
		pathMarginLabel nvarchar(100),
		pathInvsType nvarchar(100),
		pathConsultantSpeciality nvarchar(100))
INSERT INTO #pathologyTable_Br_notime_pre(
		pID4,
		surgID4,
		pathSpecimenLabel,
		pathSite,
		pathMorphLabel,
		pathMorphCDS,
		pathMarginLabel,
		pathInvsType,
		pathConsultantSpeciality)
SELECT t1.pID4,
		surgID4,
		pathSpecimenLabel,
		pathSite,
		pathMorphLabel,
		pathMorphCDS,
		pathMarginLabel,
		pathInvsType,
		pathConsultantSpeciality
FROM
(SELECT esp_PatientID pID4,
	esp_SurgeryID surgID4,
	esp_SpecimenTypeLabel pathSpecimenLabel,
	esp_SiteCodeLabel pathSite,
	esp_MorphologyLabel pathMorphLabel,
	esp_MorphologyCDS pathMorphCDS,
	esp_MarginLabel pathMarginLabel,
	esp_PathologyInvestigationTypeLabel pathInvsType,
	esp_ContactSpecialityLabel pathConsultantSpeciality
FROM PPMQuery.leeds.Pathology
WHERE esp_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID4 = t2.pID
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#pathologyTable_Br_notime') IS NOT NULL
	DROP TABLE #pathologyTable_Br_notime
SELECT * INTO #pathologyTable_Br_notime
FROM
(SELECT * FROM #pathologyTable_Br_notime_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier pathpID2, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID4 = t4.ex_PatientID
ALTER TABLE #pathologyTable_Br_notime DROP COLUMN pID4, ex_PatientID
 --SELECT * FROM #pathologyTable_Br_notime 


-- ** The next step is to join the non-dated data from all tables to  
-- ** each of the dated tables.
--
-- ** #pathologyTable_Br_time to become #pathTable_Br
IF OBJECT_ID ('tempdb..#pathTable_Br') IS NOT NULL  
	DROP TABLE #pathTable_Br
SELECT DISTINCT * INTO #pathTable_Br
FROM
	(
	SELECT pathpID1 AS pathPID,
			surgID3 AS surgeryID,
			* FROM #pathologyTable_Br_time
	) AS t1
LEFT OUTER JOIN
	(
	SELECT * FROM #pathologyTable_Br_notime
	) AS t2
ON t1.pathPID = t2.pathPID2
	AND t1.surgeryID = t2.surgID4
LEFT OUTER JOIN
	(
	SELECT * FROM #surgeryTable_Br_notime
	) AS t3
ON t1.pathPID = t3.surgPID2
	AND t1.surgeryID = t3.surgID2
ALTER TABLE #pathTable_Br DROP COLUMN pathPID1, pathPID2, surgpID2,
										surgID2, surgID3, surgID4, surgeryID
ALTER TABLE #pathTable_Br ADD pathIDkey uniqueidentifier
UPDATE #pathTable_Br SET pathIDkey = newid()

-- ** #surgeryTable_Br_time to become #surgTable_Br
IF OBJECT_ID ('tempdb..#surgTable_Br') IS NOT NULL  
	DROP TABLE #surgTable_Br
SELECT DISTINCT * INTO #surgTable_Br
FROM
	(
	SELECT surgpID1 AS surgPID,
			surgID1 AS surgeryID,
			* FROM #surgeryTable_Br_time
	) AS t1
LEFT OUTER JOIN
	(
	SELECT * FROM #pathologyTable_Br_notime
	) AS t2
ON t1.surgPID = t2.pathPID2
	AND t1.surgeryID = t2.surgID4
LEFT OUTER JOIN
	(
	SELECT * FROM #surgeryTable_Br_notime
	) AS t3
ON t1.surgPID = t3.surgPID2
	AND t1.surgeryID = t3.surgID2
ALTER TABLE #surgTable_Br DROP COLUMN surgPID1, pathPID2, surgpID2,
										surgID1, surgID2, surgID4, surgeryID
ALTER TABLE #surgTable_Br ADD surgIDkey uniqueidentifier
UPDATE #surgTable_Br SET surgIDkey = newid()


 end --

begin -- ** Investigations **
-- PPMQuery.leeds.InvestigationEx --
IF OBJECT_ID ('tempdb..#investigationTable_Br_pre1') IS NOT NULL  
	DROP TABLE #investigationTable_Br_pre1
CREATE TABLE #investigationTable_Br_pre1(
		pID int,
		investigationDate date,
		ageBandAtInvestigationDate real,
		investigationLabel nvarchar(100))
INSERT INTO #investigationTable_Br_pre1(
		pID,
		investigationDate,
		ageBandAtInvestigationDate,
		investigationLabel)
SELECT t1.pID,
		investigationDate,
		FLOOR(DATEDIFF(DAY,DOB,investigationDate)/(365.4*5)) ageBandAtInvestigationDate,
		investigationLabel
FROM
(SELECT en_PatientID pID,
		en_InvestigationDate investigationDate,
		en_InvestigationCode_CodeLabel investigationLabel
FROM PPMQuery.leeds.InvestigationEx
WHERE en_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, investigationDate DESC
-- PPMQuery.leeds.Investigations --
IF OBJECT_ID ('tempdb..#investigationTable_Br_pre2') IS NOT NULL  
	DROP TABLE #investigationTable_Br_pre2
CREATE TABLE #investigationTable_Br_pre2(
		pID2 int,
		eventDate date,
		eventDetail nvarchar(200),
		resultLabel nvarchar(100),
		typeAndSite nvarchar(250),
		invsConsultantSpeciality nvarchar(100))
INSERT INTO #investigationTable_Br_pre2(
		pID2,
		eventDate,
		eventDetail,
		resultLabel,
		typeAndSite,
		invsConsultantSpeciality)
SELECT t1.pID2,
		eventDate,
		eventDetail,
		resultLabel,
		typeAndSite,
		invsConsultantSpeciality
FROM
(SELECT en_PatientID pID2,
		en_EventDate eventDate,
		en_EventDetail eventDetail,
		en_ResultLabel resultLabel,
		en_Description typeAndSite,
		en_ContactSpecLabel invsConsultantSpeciality
FROM PPMQuery.leeds.Investigations
WHERE en_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID2 = t2.pID
ORDER BY pID2, eventDate DESC

-- Now merge the two investigations tables.
IF OBJECT_ID ('tempdb..#investigationTable_Br_pre') IS NOT NULL  
	DROP TABLE #investigationTable_Br_pre
SELECT newid() invsIDkey, * INTO #investigationTable_Br_pre
FROM(
(SELECT * FROM #investigationTable_Br_pre1) t1
JOIN
(SELECT * FROM #investigationTable_Br_pre2) t2
ON t1.pID = t2.pID2 AND t1.investigationDate = t2.eventDate
	)
ALTER TABLE #investigationTable_Br_pre DROP COLUMN pID2, eventDate
IF OBJECT_ID ('tempdb..#investigationTable_Br') IS NOT NULL  
	DROP TABLE #investigationTable_Br
SELECT * INTO #investigationTable_Br
FROM
(SELECT * FROM #investigationTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier invspID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE investigationDate < '2012-04-13'
ALTER TABLE #investigationTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #investigationTable_Br SET ageBandAtInvestigationDate = 17 WHERE ageBandAtInvestigationDate > 17
 --SELECT * FROM #investigationTable_Br
end --

begin -- ** PPMQuery.leeds.Diagnosis **
IF OBJECT_ID ('tempdb..#diagnosisTable_Br_pre') IS NOT NULL  
	DROP TABLE #diagnosisTable_Br_pre
CREATE TABLE #diagnosisTable_Br_pre(
		diagIDkey uniqueidentifier, pID int,
		diagnosisDate date,
		ageBandAtDiagnosisDate real,
		tumourLabel nvarchar(100),
		nodeLabel nvarchar(100),
		metastatsisLabel nvarchar(100),
		diagSiteLabel nvarchar(100),
		performanceStatusLabel nvarchar(100),
		gradeLabel nvarchar(100),
		stageLabel nvarchar(100),
		icd10Code nvarchar(3),
		morphLabel nvarchar(100),
		morphCode nvarchar(10),
		ERstatus int,
		PRstatus int,
		HER2status int,
		cancerStatusLabel nvarchar(50),
		disPhase nvarchar(100),
		diagConsultantSpeciality nvarchar(100),
	   diagSurvStatus bit,
	   diagSurvTime real)
INSERT INTO #diagnosisTable_Br_pre(
		diagIDkey, pID,
		diagnosisDate,
		ageBandAtDiagnosisDate,
		tumourLabel,
		nodeLabel,
		metastatsisLabel,
		diagSiteLabel,
		performanceStatusLabel,
		gradeLabel,
		stageLabel,
		icd10Code,
		morphLabel,
		morphCode,
		ERstatus,
		PRstatus,
		HER2status,
		cancerStatusLabel,
		disPhase,
		diagConsultantSpeciality,
	   diagSurvStatus,
	   diagSurvTime)
SELECT diagIDkey, t1.pID,
		diagnosisDate,
		FLOOR(DATEDIFF(DAY,DOB,diagnosisDate)/(365.4*5)) ageBandAtDiagnosisDate,
		tumourLabel,
		nodeLabel,
		metastatsisLabel,
		diagSiteLabel,
		performanceStatusLabel,
		gradeLabel,
		stageLabel,
		icd10Code,
		morphLabel,
		morphCode,
		ERstatus,
		PRstatus,
		HER2status,
		cancerStatusLabel,
		disPhase,
		diagConsultantSpeciality,
	   diagSurvStatus,
	   diagSurvTime
FROM
(SELECT newid() diagIDkey, dx_PatientID pID,
		dx_DiagnosisDate diagnosisDate,
		dx_TumourLabel tumourLabel,
		dx_NodeLabel nodeLabel,
		dx_MetastasisLabel metastatsisLabel,
		dx_SiteLabel diagSiteLabel,
		dx_PerformanceStatusLabel performanceStatusLabel,
		dx_GradeCodeLabel gradeLabel,
		dx_StageLabel stageLabel,
		dx_ICD10CDS3 icd10Code,
		dx_MorphologyLabel morphLabel,
		dx_MorphologyCDS morphCode,
		dx_EstrogenReceptorStatus ERstatus,
		dx_ProgesteroneReceptorStatus PRstatus,
		dx_Her2Status HER2status,
		dx_CancerStatusLabel cancerStatusLabel,
		dx_DiseasePhaseLabel disPhase,
		dx_ContactSpecialityLabel diagConsultantSpeciality,
	   dx_SurvivalStatus diagSurvStatus,
	   dx_SurvivalTime diagSurvTime
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, diagnosisDate DESC

IF OBJECT_ID ('tempdb..#diagnosisTable_Br') IS NOT NULL  
	DROP TABLE #diagnosisTable_Br
SELECT * INTO #diagnosisTable_Br
FROM
(SELECT * FROM #diagnosisTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier diagpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE diagnosisDate < '2012-04-13'
ALTER TABLE #diagnosisTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #diagnosisTable_Br SET ageBandAtDiagnosisDate = 17 WHERE ageBandAtDiagnosisDate > 17
 --SELECT * FROM #diagnosisTable_Br ORDER BY diagpID, diagnosisDate
end --

begin -- ** PPMQuery.leeds.Patients **
IF OBJECT_ID ('tempdb..#demogTable_Br_pre') IS NOT NULL
	DROP TABLE #demogTable_Br_pre
CREATE TABLE #demogTable_Br_pre(
		patiIDkey uniqueidentifier, pID int,
		sexLabel nvarchar(100),
		ccgID nvarchar(50),
		imdqLabel int,
		ethnicLabel nvarchar(100))
INSERT INTO #demogTable_Br_pre(
		patiIDkey, pID,
		sexLabel,
		ccgID,
		imdqLabel,
		ethnicLabel)			
SELECT newid() patiIDkey, pt_PatientID pID,
		pt_SexLabel sexLabel,
		pt_CCGID ccgID,
		pt_RANKIMDQuintile imdqLabel,
		pt_EthnicOriginLabel ethnicLabel
FROM PPMQuery.leeds.Patients
WHERE pt_PatientID IN (SELECT * FROM #breastPatients)
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#demogTable_Br') IS NOT NULL
	DROP TABLE #demogTable_Br
SELECT * INTO #demogTable_Br
FROM
(SELECT * FROM #demogTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier patipID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
ALTER TABLE #demogTable_Br
DROP COLUMN pID, ex_PatientID
-- SELECT * FROM #demogTable_Br
end --

begin -- ** deathDate **
IF OBJECT_ID ('tempdb..#deathDate_Br_pre') IS NOT NULL
	DROP TABLE #deathDate_Br_pre
CREATE TABLE #deathDate_Br_pre(
		dodIDkey uniqueidentifier, pID int,
		deathDate date,
		ageBandAtDeathDate real)
INSERT INTO #deathDate_Br_pre(
		dodIDkey, pID,
		deathDate,
		ageBandAtDeathDate)
SELECT dodIDkey, t1.pID,
		deathDate,
		FLOOR(DATEDIFF(DAY,DOB,deathDate)/(365.4*5)) ageBandAtDeathDate
FROM
(SELECT newid() dodIDkey, pt_PatientID pID,
		pt_DeathDate deathDate
FROM PPMQuery.leeds.Patients
WHERE pt_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID DESC

IF OBJECT_ID ('tempdb..#deathDate_Br') IS NOT NULL
	DROP TABLE #deathDate_Br
SELECT * INTO #deathDate_Br
FROM
(SELECT * FROM #deathDate_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier dodpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
ALTER TABLE #deathDate_Br DROP COLUMN pID, ex_PatientID
UPDATE #deathDate_Br SET ageBandAtDeathDate = 17 WHERE ageBandAtDeathDate > 17
UPDATE #deathDate_Br SET deathDate = NULL WHERE deathDate > '2012-04-13'
UPDATE #deathDate_Br SET ageBandAtDeathDate = NULL WHERE deathDate > '2012-04-13'
--SELECT * FROM #deathDate_Br ORDER BY dodpID, deathDate
end --

begin -- ** PPMQuery.leeds.MDTReview **
IF OBJECT_ID ('tempdb..#MDTrevTable_Br_pre') IS NOT NULL
	DROP TABLE #MDTrevTable_Br_pre
CREATE TABLE #MDTrevTable_Br_pre(
		mdtrIDkey uniqueidentifier, pID int,
		mdtrDate date,
		ageBandAtMDTrevDate real,
		MDTrevTeamName nvarchar(100),
		MDTrevCaseType nvarchar(30),
	   MDTrevWhoRequest nvarchar(30),
	   mdtrConsultantSpeciality nvarchar(100),
	   mdtrSurvStatus bit,
	   mdtrSurvTime real)
INSERT INTO #MDTrevTable_Br_pre(
		mdtrIDkey, pID,
		mdtrDate,
		ageBandAtMDTrevDate,
		MDTrevTeamName,
		MDTrevCaseType,
	   MDTrevWhoRequest,
	   mdtrConsultantSpeciality,
	   mdtrSurvStatus,
	   mdtrSurvTime)
SELECT mdtrIDkey, t1.pID,
		mdtrDate,
		FLOOR(DATEDIFF(DAY,DOB,mdtrDate)/(365.4*5)) ageBandAtMDTrevDate,
		MDTrevTeamName,
		MDTrevCaseType,
	   MDTrevWhoRequest,
	   mdtrConsultantSpeciality,
	   mdtrSurvStatus,
	   mdtrSurvTime
FROM
(SELECT newid() mdtrIDkey, ev_PatientID pID,
		ev_EventDate mdtrDate,
		ev_TeamName MDTrevTeamName,
		ev_CaseTypeLabel MDTrevCaseType,
	    ev_RequestCodeLabel MDTrevWhoRequest,
	    ev_SubmittedByContactSpecialityLabel mdtrConsultantSpeciality,
	    ev_SurvivalStatus mdtrSurvStatus,
	    ev_SurvivalTime mdtrSurvTime
FROM PPMQuery.leeds.MDTReview
WHERE ev_PatientID IN (SELECT * FROM #breastPatients)) t1
JOIN
(SELECT DISTINCT dx_PatientID pID,
		dx_BirthDate DOB
FROM PPMQuery.leeds.Diagnosis
WHERE dx_PatientID IN (SELECT * FROM #breastPatients)) t2
ON t1.pID = t2.pID
ORDER BY pID, mdtrDate DESC

IF OBJECT_ID ('tempdb..#MDTrevTable_Br') IS NOT NULL
	DROP TABLE #MDTrevTable_Br
SELECT * INTO #MDTrevTable_Br
FROM
(SELECT * FROM #MDTrevTable_Br_pre) t3
JOIN
(SELECT DISTINCT ex_CodedIdentifier mdtrpID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #breastPatients))) t4
ON t3.pID = t4.ex_PatientID
WHERE mdtrDate < '2012-04-13'
ALTER TABLE #MDTrevTable_Br DROP COLUMN pID, ex_PatientID
UPDATE #MDTrevTable_Br SET ageBandAtMDTrevDate = 17 WHERE ageBandAtMDTrevDate > 17
--SELECT * FROM #MDTrevTable_Br
end --

begin -- ** Worsening **
IF OBJECT_ID ('tempdb..#recurrences_Br') IS NOT NULL
	DROP TABLE #recurrences_Br
CREATE TABLE #recurrences_Br(
		recurpID uniqueidentifier,
		DOB date,
		DxDate date,
		DateRec1 date,
		DateRec2 date,
		DateRec3 date,
		DateRec4 date,
		DateRec5 date,
		DateRec6 date,
		DateRec7 date,
		DateRec8 date,
		DateRec9 date,
		DateRec10 date,
		DateRec11 date)
INSERT INTO #recurrences_Br(
		recurpID,
		DOB,
		DxDate,
		DateRec1,
		DateRec2,
		DateRec3,
		DateRec4,
		DateRec5,
		DateRec6,
		DateRec7,
		DateRec8,
		DateRec9,
		DateRec10,
		DateRec11)
SELECT DISTINCT
		ex_CodedIdentifier recurpID,
		DOB,
		DxDate,
		DateRec1,
		DateRec2,
		DateRec3,
		DateRec4,
		DateRec5,
		DateRec6,
		DateRec7,
		DateRec8,
		DateRec9,
		DateRec10,
		DateRec11
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL AS t1
JOIN
	(
	SELECT dx_PatientID, dx_BirthDate AS DOB
	FROM PPMQuery.leeds.Diagnosis
	) t2
ON t1.ex_PatientID = t2.dx_PatientID
WHERE ex_PatientID in
	(SELECT DISTINCT dx_PatientID recurpID
		FROM PPMQuery.leeds.Diagnosis
		WHERE dx_PatientID IN (SELECT * FROM #breastPatients))
		AND Cohort = 'breast'
ORDER BY recurpID
-- This table is initially constructed without an uniqueidentifier
-- because of issues with duplicates in the ACNRes table. I add
-- it now.
ALTER TABLE #recurrences_Br ADD recurIDkey uniqueidentifier
UPDATE #recurrences_Br SET recurIDkey = newid()
-- SELECT * FROM #recurrences_Br ORDER BY recurpID


-- ** worsening **
-- ** This table collates all progression and recurrences (hereadter 
-- ** called "worsening") into one column.
IF OBJECT_ID ('tempdb..#oneColWorsening_Br') IS NOT NULL
	DROP TABLE #oneColWorsening_Br
SELECT * INTO #oneColWorsening_Br
FROM(
	SELECT newid() worsenIDkey, recurpID worsenpID, prevWorsenCnt, worseningDate, DOB, CAST(FLOOR(DATEDIFF(DAY, DOB, worseningDate)/(365.4*5)) AS real) AS ageBandAtWorseningDate
	FROM #recurrences_Br
	UNPIVOT(
		worseningDate
		FOR prevWorsenCnt IN (DateRec1,
						DateRec2,
						DateRec3,
						DateRec4,
						DateRec5,
						DateRec6,
						DateRec7,
						DateRec8,
						DateRec9,
						DateRec10,
						DateRec11)
			) t
	) tt	
UPDATE #oneColWorsening_Br 
	SET prevWorsenCnt = (
		CASE prevWorsenCnt
			WHEN 'DateRec1' THEN 0
			WHEN 'DateRec2' THEN 1
			WHEN 'DateRec3' THEN 2
			WHEN 'DateRec4' THEN 3
			WHEN 'DateRec5' THEN 4
			WHEN 'DateRec6' THEN 5
			WHEN 'DateRec7' THEN 6
			WHEN 'DateRec8' THEN 7
			WHEN 'DateRec9' THEN 8
			WHEN 'DateRec10' THEN 9
			WHEN 'DateRec11' THEN 10
		END)
UPDATE #oneColWorsening_Br SET ageBandAtWorseningDate = 17 WHERE ageBandAtWorseningDate > 17
-- SELECT * FROM #oneColWorsening_Br ORDER BY worsenpID, worseningDate
end --

-- *******************************************************************
-- ** Combines all temp tables into one with a continuous time column.
-- *******************************************************************
begin --
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre
SELECT DISTINCT * INTO #combinedTable_Br_pre
FROM(
	SELECT --unionID,
			unionTimeStamp AS ts,
			unionPID AS pID,
			unionSurvStatus,
			unionSurvTime,
			unionConsultantSpeciality,
			-- ** The following is from #consultTable_Br.
			consultationDate,
			ageBandAtConsultationDate,
			consultantRole,
			-- ** The following is from #annotationsTable_Br.
			dictateDate,
			ageBandAtDictateDate,
			annotationHeadline,
			-- ** The following is from #outpatientTable_Br.
			clinicDate,
			ageBandAtClinicDate,
			clinicType,
			clinicContactType,
			-- ** The following is from #admissionsTable_Br.
			admissionDate,
			ageBandAtAdmissionDate,
			admissionMethod,
			dischargeDate,
			ageBandAtDischargeDate,
			admissionDuration,
			admissionDurationLTHT,
			admissionSource,
			clinicianType,
			dischargeReason,
			-- ** The following is from #wardstaysTable_Br.
			wardAdmissionDate,
			ageBandAtWardAdmissionDate,
			wardStayStartDate,
			ageBandAtWardStartDate,
			wardStayEndDate,
			ageBandAtWardEndDate,
			admissionToStayStartDuration,
			wardStayDuration,
			wardLabel,
			wardStartActivityLabel,
			wardEndActivityLabel,
			-- ** The following is from #radioTable_Br.
			radioEventDate,
			ageBandAtRadioEventDate,
			radiActionStatusLabel,
			radiSiteLabel,
			radiIntentLabel,
			-- ** The following is from #radioExTable_Br
			radioStartDate,
			ageBandAtRadioStartDate,
			radioEndDate,
			ageBandAtRadioEndDate,
			radioDuration,
			radioTypeLabel,
			-- ** The following is from #chemoTable_Br.
			regimenID,
			cycleNum,
			cycleStartDate,
			ageBandAtCycleStartDate,
			drugStartDate,
			ageBandAtDrugStartDate,
			regStartDate,
			ageBandAtRegStartDate,
			regEndDate,
			ageBandAtRegEndDate,
			regDecisionDate,
			ageBandAtRegDecisionDate,
			heightValue,
			weightValue,
			regimenIntentLabel,
			regimenDrugLabel,
			regimenDuration,
			drugLabel,
			drugDeliveryRouteLabel,
			drugReqDose,
			drugDose,
			drugFreq,
			cycleActionStatus,
			regOutcome,
			regLabel,
			expDurationOfCycle,
			drugTherapyType,
			stoppingReason,
			trialYesNo,
			-- ** The following is from #surgTable_Br & #pathTable_Br.
			surgeryDate,
			ageBandAtSurgeryDate,
			pathSpecimenLabel,
			pathSite,
			pathMorphLabel,
			pathMorphCDS,
			pathMarginLabel,
			pathInvsType,
			surgActionStatusLabel,
			surgIntent,
			operationReason,
			procedureLabel,
			outcomeLabel,
			residualDisease,
			-- ** The following is from #investigationTable_Br.
			investigationDate,
			ageBandAtInvestigationDate,
			investigationLabel,
			eventDetail,			
			resultLabel,
			typeAndSite,
			-- ** The following is from #diagnosisTable_Br.
			diagnosisDate,
			ageBandAtDiagnosisDate,
			tumourLabel,
			nodeLabel,
			metastatsisLabel,
			diagSiteLabel,
			performanceStatusLabel,
			gradeLabel,
			stageLabel,
			icd10Code,
			morphLabel,
			morphCode,
			ERstatus,
			PRstatus,
			HER2status,
			cancerStatusLabel,
			disPhase,
			-- ** The following is from #deathDate_Br.
			deathDate,
			ageBandAtDeathDate,
			-- ** The following is from #MDTrevTable_Br.
			mdtrDate,
			ageBandAtMDTrevDate,
			MDTrevTeamName,
			MDTrevCaseType,
			MDTrevWhoRequest,
			-- ** The following is from #oneColWorsening_Br.			
			prevWorsenCnt,
			worseningDate,
			ageBandAtWorseningDate
	FROM(
		SELECT * FROM( -- t14
			SELECT * FROM( -- t13
				SELECT * FROM( -- t12
					SELECT * FROM( -- t11
						SELECT * FROM( -- t10
							SELECT * FROM( -- t9
								SELECT * FROM( -- t8
									SELECT * FROM( -- t7
										SELECT * FROM( -- t6
											SELECT * FROM( -- t5
												SELECT * FROM( -- t4
													SELECT * FROM( -- t3
														SELECT * FROM( -- t2
															SELECT * FROM( -- t1
																SELECT consIDkey unionID, conspID unionPID, consultationDate unionTimeStamp, consSurvStatus unionSurvStatus, consSurvTime unionSurvTime, consConsultantSpeciality unionConsultantSpeciality FROM #consultTable_Br WHERE consultationDate IS NOT NULL
																UNION ALL
																SELECT annotIDkey unionID, annotpID unionPID, dictateDate unionTimeStamp, NULL AS unionSurvStatus, NULL AS unionSurvTime, NULL AS unionConsultantSpeciality FROM #annotationsTable_Br WHERE dictateDate IS NOT NULL
																UNION ALL
																SELECT outpIDkey unionID, outppID unionPID, clinicDate unionTimeStamp, ouptSurvStatus unionSurvStatus, ouptSurvTime unionSurvTime, outpContactSpeciality unionConsultantSpeciality FROM #outpatientTable_Br WHERE clinicDate IS NOT NULL
																UNION ALL
																SELECT admiIDkey unionID, admipID unionPID, admissionDate unionTimeStamp, admiSurvStatus unionSurvStatus, admiSurvTime unionSurvTime, admiConsultantSpeciality unionConsultantSpeciality FROM #admissionsTable_Br WHERE admissionDate IS NOT NULL
																UNION ALL
																SELECT admiIDkey unionID, admipID unionPID, dischargeDate unionTimeStamp, admiSurvStatus unionSurvStatus, admiSurvTime unionSurvTime, NULL AS unionConsultantSpeciality FROM #admissionsTable_Br WHERE dischargeDate IS NOT NULL
																UNION ALL
																SELECT wstaIDkey unionID, wstapID unionPID, wardadmissionDate unionTimeStamp, wstaSurvStatus unionSurvStatus, wstaSurvTime unionSurvTime, wardConsultantSpeciality unionConsultantSpeciality FROM #wardstaysTable_Br WHERE wardadmissionDate IS NOT NULL
																UNION ALL
																SELECT wstaIDkey unionID, wstapID unionPID, wardStayStartDate unionTimeStamp, wstaSurvStatus unionSurvStatus, wstaSurvTime unionSurvTime, wardConsultantSpeciality unionConsultantSpeciality FROM #wardstaysTable_Br WHERE wardStayStartDate IS NOT NULL
																UNION ALL
																SELECT wstaIDkey unionID, wstapID unionPID, wardStayEndDate unionTimeStamp, wstaSurvStatus unionSurvStatus, wstaSurvTime unionSurvTime, wardConsultantSpeciality unionConsultantSpeciality FROM #wardstaysTable_Br WHERE wardStayEndDate IS NOT NULL
																UNION ALL
																SELECT radiIDkey unionID, radipID unionPID, radioEventDate unionTimeStamp, radiSurvStatus unionSurvStatus, radiSurvTime unionSurvTime, NULL AS unionConsultantSpeciality FROM #radioTable_Br WHERE radioEventDate IS NOT NULL
																UNION ALL
																SELECT radxIDkey unionID, radxpID unionPID, radioStartDate unionTimeStamp, NULL AS unionSurvStatus, NULL AS unionSurvTime, NULL AS unionConsultantSpeciality FROM #radioExTable_Br WHERE radioStartDate IS NOT NULL
																UNION ALL
																SELECT radxIDkey unionID, radxpID unionPID, radioEndDate unionTimeStamp, NULL AS unionSurvStatus, NULL AS unionSurvTime, NULL AS unionConsultantSpeciality FROM #radioExTable_Br WHERE radioEndDate IS NOT NULL
																UNION ALL
																SELECT chemIDkey unionID, chemPID unionPID, cycleStartDate unionTimeStamp, chemSurvStatus unionSurvStatus, chemSurvTime unionSurvTime, drugConsultantSpeciality_drug unionConsultantSpeciality FROM #chemoTable_Br WHERE cycleStartDate IS NOT NULL
																UNION ALL
																SELECT chemIDkey unionID, chemPID unionPID, drugStartDate unionTimeStamp, chemSurvStatus unionSurvStatus, chemSurvTime unionSurvTime, drugConsultantSpeciality_drug unionConsultantSpeciality FROM #chemoTable_Br WHERE drugStartDate IS NOT NULL
																UNION ALL
																SELECT chemIDkey unionID, chemPID unionPID, regStartDate unionTimeStamp, chemSurvStatus unionSurvStatus, chemSurvTime unionSurvTime, drugConsultantSpeciality_drug unionConsultantSpeciality FROM #chemoTable_Br WHERE regStartDate IS NOT NULL
																UNION ALL
																SELECT chemIDkey unionID, chemPID unionPID, regEndDate unionTimeStamp, chemSurvStatus unionSurvStatus, chemSurvTime unionSurvTime, drugConsultantSpeciality_drug unionConsultantSpeciality FROM #chemoTable_Br WHERE regEndDate IS NOT NULL
																UNION ALL
																SELECT chemIDkey unionID, chemPID unionPID, regDecisionDate unionTimeStamp, chemSurvStatus unionSurvStatus, chemSurvTime unionSurvTime, drugConsultantSpeciality_drug unionConsultantSpeciality FROM #chemoTable_Br WHERE regDecisionDate IS NOT NULL
																UNION ALL
																SELECT surgIDkey unionID, surgpID unionPID, surgeryDate unionTimeStamp, surgSurvStatus unionSurvStatus, surgSurvTime unionSurvTime, surgConsultantSpeciality AS unionConsultantSpeciality FROM #surgTable_Br WHERE surgeryDate IS NOT NULL
																UNION ALL
																SELECT pathIDkey unionID, pathpID unionPID, pathDate unionTimeStamp, surgSurvStatus unionSurvStatus, surgSurvTime unionSurvTime, pathConsultantSpeciality AS unionConsultantSpeciality FROM #pathTable_Br WHERE pathDate IS NOT NULL
																UNION ALL
																SELECT invsIDkey unionID, invspID unionPID, investigationDate unionTimeStamp, NULL AS unionSurvStatus, NULL AS unionSurvTime, invsConsultantSpeciality unionConsultantSpeciality FROM #investigationTable_Br WHERE investigationDate IS NOT NULL
																UNION ALL
																SELECT diagIDkey unionID, diagpID unionPID, diagnosisDate unionTimeStamp, diagSurvStatus unionSurvStatus, diagSurvTime unionSurvTime, diagConsultantSpeciality unionConsultantSpeciality FROM #diagnosisTable_Br WHERE diagnosisDate IS NOT NULL
																UNION ALL
																SELECT mdtrIDkey unionID, mdtrpID unionPID, mdtrDate unionTimeStamp, mdtrSurvStatus unionSurvStatus, mdtrSurvTime unionSurvTime, mdtrConsultantSpeciality unionConsultantSpeciality FROM #MDTrevTable_Br WHERE mdtrDate IS NOT NULL
																UNION ALL
																SELECT dodIDkey unionID, dodpID unionPID, deathDate unionTimeStamp, NULL AS unionSurvStatus, NULL AS unionSurvTime, NULL AS unionConsultantSpeciality FROM #deathDate_Br WHERE deathDate IS NOT NULL															
																		) t1
														LEFT JOIN
														#consultTable_Br
														ON unionID = #consultTable_Br.consIDkey
															) t2 	
													LEFT JOIN
													#annotationsTable_Br
													ON unionID = #annotationsTable_Br.annotIDkey
													) t3
												LEFT JOIN
												#outpatientTable_Br
												ON unionID = #outpatientTable_Br.outpIDkey
												) t4
											LEFT JOIN
											#admissionsTable_Br
											ON unionID = #admissionsTable_Br.admiIDkey
											) t5
										LEFT JOIN
										#wardstaysTable_Br
										ON unionID = #wardstaysTable_Br.wstaIDkey
										) t6
									LEFT JOIN
									#radioTable_Br
									ON unionID = #radioTable_Br.radiIDkey
									) t7
								LEFT JOIN
								#radioExTable_Br
								ON unionID = #radioExTable_Br.radxIDkey
										) t8
							LEFT JOIN
							#chemoTable_Br
							ON unionID = #chemoTable_Br.chemIDkey
							) t9
						LEFT JOIN
						#surgTable_Br
						ON unionID = #surgTable_Br.surgIDkey
						) t10
					LEFT JOIN
					#investigationTable_Br
					ON unionID = #investigationTable_Br.invsIDkey
							) t11
				LEFT JOIN
				#diagnosisTable_Br
				ON unionID = #diagnosisTable_Br.diagIDkey
				) t12
			LEFT JOIN
			#MDTrevTable_Br
			ON unionID = #MDTrevTable_Br.mdtrIDkey
			) t13
		LEFT JOIN
		#deathDate_Br
		ON unionID = #deathDate_Br.dodIDkey
		) t14
		FULL OUTER JOIN
		#oneColWorsening_Br
		ON unionpID = #oneColWorsening_Br.worsenpID AND unionTimeStamp = #oneColWorsening_Br.worseningDate
		) t15
	) tt
-- ** Add any validated worsening events for which there are no PPM events.
IF OBJECT_ID ('tempdb..#addOnTable') IS NOT NULL
	DROP TABLE #addOnTable
SELECT * INTO #addOnTable
FROM 
	(
	SELECT *
	FROM #combinedTable_Br_pre
	WHERE pID IS NULL AND ts IS NULL
	) t3
JOIN
	(
	SELECT worsenpID, t1.prevWorsenCnt AS prevWorsenCnt2, t1.worseningDate AS worseningDate2
	FROM
		(
		SELECT *
		FROM #oneColWorsening_Br
		) t1
	RIGHT OUTER JOIN
		(
		SELECT *
		FROM #combinedTable_Br_pre
		WHERE pID IS NULL AND ts IS NULL
		) t2
	ON t1.prevWorsenCnt = t2.prevWorsenCnt AND t1.worseningDate = t2.worseningDate
	EXCEPT
	SELECT t1.pID, t1.prevWorsenCnt, t1.worseningDate
	FROM
		(
		SELECT *
		FROM #combinedTable_Br_pre
		) t1
	RIGHT OUTER JOIN
		(
		SELECT *
		FROM #combinedTable_Br_pre
		WHERE pID IS NULL AND ts IS NULL
		) t2
	ON t1.prevWorsenCnt = t2.prevWorsenCnt AND t1.worseningDate = t2.worseningDate
	) t4
	ON t3.prevWorsenCnt = t4.prevWorsenCnt2 AND t3.worseningDate = t4.worseningDate2
ORDER BY t3.pID, ts
UPDATE #addOnTable SET pID = worsenpID
UPDATE #addOnTable SET ts = worseningDate2
ALTER TABLE #addOnTable DROP COLUMN worsenpID, worseningDate2, prevWorsenCnt2
INSERT INTO #combinedTable_Br_pre SELECT * FROM #addOnTable
DELETE FROM #combinedTable_Br_pre WHERE pID IS NULL AND ts IS NULL
-- ** This next update handles an issue where a there was a carriage return within a field. This
-- ** might or might not pop up again. All that would need changing would be the column of interest,
-- ** in this case, called operationReason.
UPDATE #combinedTable_Br_pre SET operationReason = replace(operationReason, char(13) + char(10), ' ')

-- ** Add a column that keeps track of the age band at every event date.
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre2') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre2
SELECT * INTO #combinedTable_Br_pre2
FROM
	(
	SELECT DISTINCT *
	FROM #combinedTable_Br_pre AS t4
	LEFT JOIN
	(
	-- Select distinct combinations of pID, ts and age band.
	SELECT DISTINCT pID AS pIDremove, ts AS TSremove, ageBand
	FROM 
		(
		SELECT 
		pID, ts,
		ageBandAtConsultationDate,
		ageBandAtDictateDate,
		ageBandAtClinicDate,
		ageBandAtAdmissionDate,
		ageBandAtDischargeDate,
		ageBandAtWardadmissionDate,
		ageBandAtWardStartDate,
		ageBandAtWardEndDate,
		ageBandAtRadioEventDate,
		--ageBandAtRadioStartDate,
		--ageBandAtRadioEndDate,
		ageBandAtCycleStartDate,
		ageBandAtDrugStartDate,
		ageBandAtRegStartDate,
		ageBandAtRegEndDate,
		ageBandAtRegDecisionDate,
		ageBandAtSurgeryDate,
		--ageBandAtInvestigationDate,
		--ageBandAtEventDate,
		ageBandAtDiagnosisDate,
		ageBandAtDeathDate,
		ageBandAtMDTrevDate,
		ageBandAtWorseningDate
		FROM #combinedTable_Br_pre
		) t1
		UNPIVOT(
			ageBand
			FOR ageBandTitle IN (ageBandAtConsultationDate,
								ageBandAtDictateDate,
								ageBandAtClinicDate,
								ageBandAtAdmissionDate,
								ageBandAtDischargeDate,
								ageBandAtWardadmissionDate,
								ageBandAtWardStartDate,
								ageBandAtWardEndDate,
								ageBandAtRadioEventDate,
								--ageBandAtRadioStartDate,
								--ageBandAtRadioEndDate,
								ageBandAtCycleStartDate,
								ageBandAtDrugStartDate,
								ageBandAtRegStartDate,
								ageBandAtRegEndDate,
								ageBandAtRegDecisionDate,
								ageBandAtSurgeryDate,
								--ageBandAtInvestigationDate,
								--ageBandAtEventDate,
								ageBandAtDiagnosisDate,
								ageBandAtDeathDate,
								ageBandAtMDTrevDate,
								ageBandAtWorseningDate)
				) t2
	) t3
	ON t4.pID = t3.pIDremove AND t4.ts = t3.TSremove
	) t5
ALTER TABLE #combinedTable_Br_pre2 DROP COLUMN pIDremove, TSremove

-- ** Add column that keeps track of days since the primary diagnosis.
-- **
-- ** Positive values mean the event occured after the DxDate and 
-- ** negative values before. There are some extreme cases of chemo
-- ** events occurring 10 years previous to the diagnosis of interest,
-- ** suggesting that the cancer of interest is not the first cancer.
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre3') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre3
SELECT * INTO #combinedTable_Br_pre3
FROM
	(
	SELECT *, DATEDIFF(day, t2.DxDate, ts) AS daysProximityToPrimaryDiag
	FROM #combinedTable_Br_pre2 AS t1
LEFT JOIN
	(
	SELECT DISTINCT ex_CodedIdentifier pID2remove, DxDate
	FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
	WHERE ex_PatientID IN (
		SELECT DISTINCT dx_PatientID pID1remove
		FROM PPMQuery.leeds.Diagnosis
		WHERE dx_PatientID IN (SELECT * FROM #breastPatients))
		AND ptCohort = 'breast'
	) t2
ON t1.pID = t2.pID2remove
	) t3
ORDER BY pID, ts
ALTER TABLE #combinedTable_Br_pre3 DROP COLUMN pID2remove, DxDate

-- ** Add the demographic data and a row ID for each record.
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre4') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre4
SELECT newid() rowID, * INTO #combinedTable_Br_pre4
FROM
	(
	SELECT DISTINCT *
	FROM
		#combinedTable_Br_pre3 AS t1
	JOIN
		#demogTable_Br AS t2
	ON t1.pID = t2.patipID
	) t
ALTER TABLE #combinedTable_Br_pre4 DROP COLUMN patiIDkey, patipID

-- ** Add a column that contains an indicator of radiotherapy for
-- ** each timestamp.
-- ** This section defines the boundaries of radiotherapy. The 
-- ** logic considers radioStartDate, radioEndDate and radioEventDate
-- ** to figure out what duration the radiological treatment covers.
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre5') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre5
IF OBJECT_ID ('tempdb..#TreatmentBlockDates_radio') IS NOT NULL
	DROP TABLE #TreatmentBlockDates_radio
SELECT pID7, radioTreatmentStart, radioTreatmentEnd INTO #TreatmentBlockDates_radio
FROM
	(
	SELECT pID6 AS pID7, THE_radioTreatmentStart AS radioTreatmentStart, THE_radioTreatmentEnd AS radioTreatmentEnd
	FROM
	(
		-- ** Merges overlapping radiotherapy durations.
		SELECT pID4 AS pID6, prevEndOverlapsThisStart,
			radioTreatmentStart AS THE_radioTreatmentStart,
			(CASE
				WHEN prevEndOverlapsThisStart = 0 AND nextStartOverlapsThisEnd = 1 THEN
					LEAD(radioTreatmentEnd) OVER(PARTITION BY pID4 ORDER BY radioTreatmentStart)
				ELSE radioTreatmentEnd
			END) AS THE_radioTreatmentEnd
		FROM
		(
			-- ** Finds which selected radiotherapies durations overlap.
			SELECT *,
				(CASE
					WHEN (LAG(radioTreatmentEnd) OVER(PARTITION BY pID4 ORDER BY radioTreatmentStart)) > radioTreatmentStart THEN
						-- ...then the previous radiotherapy overlaps.
						1
					ELSE 0
				END) AS prevEndOverlapsThisStart,
				(CASE
					WHEN (LEAD(radioTreatmentStart) OVER(PARTITION BY pID4 ORDER BY radioTreatmentStart)) < radioTreatmentEnd THEN
						-- ...then the subsequent radiotherapy overlaps.
						1
					ELSE 0
				END) AS nextStartOverlapsThisEnd
			FROM
			(
				-- ** Finds the minimum start date for common end dates.
				SELECT DISTINCT pID3 AS pID4, MIN(radioTreatmentStart) OVER(PARTITION BY pID3, radioTreatmentEnd) AS radioTreatmentStart,
						radioTreatmentEnd
				FROM		
				(	
					-- ** Finds the maximum end date for common start dates.
					SELECT DISTINCT pID AS pID3, radioTreatmentStart,
								MAX(radioTreatmentEnd) OVER(PARTITION BY pID, radioTreatmentStart) AS radioTreatmentEnd
					FROM
					(
						-- ** Selects all rows that have a timestamp relating to radiotherapy.
						SELECT pID, ts, radioStartDate, radioEndDate, radioEventDate, radioDuration,
							(CASE
								WHEN radioStartDate IS NOT NULL THEN
									radioStartDate
								WHEN radioEndDate IS NOT NULL THEN
									DATEADD(d, -radioDuration, radioEndDate)
								WHEN radioEventDate IS NOT NULL THEN
									radioEventDate
								ELSE
									NULL -- ** Should never happen.
							END) AS radioTreatmentStart,
							(CASE
								WHEN radioEndDate IS NOT NULL THEN
									radioEndDate
								WHEN radioStartDate IS NOT NULL THEN
									DATEADD(d, radioDuration, radioStartDate)
								WHEN radioEventDate IS NOT NULL THEN
									DATEADD(d, radioDuration, radioEventDate)
								ELSE
									NULL -- ** Should only be returned if radioDuration is null.
							END) AS radioTreatmentEnd
						FROM #combinedTable_Br_pre4
						WHERE radioEventDate IS NOT NULL OR radioEndDate IS NOT NULL OR radioStartDate IS NOT NULL
					) t3
					WHERE radioTreatmentEnd IS NOT NULL
					GROUP BY pID, radioTreatmentStart, radioTreatmentEnd
				) t4
				GROUP BY pID3, radioTreatmentEnd, radioTreatmentStart
			) t5
		) t6
		WHERE NOT (prevEndOverlapsThisStart = 1 AND nextStartOverlapsThisEnd = 1)
	) t7
	WHERE prevEndOverlapsThisStart != 1
) t8
SELECT * INTO #combinedTable_Br_pre5
FROM
#combinedTable_Br_pre4 AS t10
LEFT OUTER JOIN
	(
	-- ** Select and flag timestamps from combined column 
	-- ** that are within a radiotherapy duration.
	SELECT DISTINCT rowID8, 1 AS treatmentBlock_radio
	FROM
		(
		-- ** Selects identifiers from the combined table.
		SELECT rowID AS rowID8, pID AS pID8, ts AS ts8
		FROM
		#combinedTable_Br_pre4
		) t8
	JOIN
		#TreatmentBlockDates_radio AS t9
	ON t8.pID8 = t9.pID7
	WHERE ts8 BETWEEN radioTreatmentStart AND radioTreatmentEnd		
	) t11
ON t10.rowID = t11.rowID8
ORDER BY pID, ts
ALTER TABLE #combinedTable_Br_pre5 DROP COLUMN rowID8
UPDATE #combinedTable_Br_pre5 SET treatmentBlock_radio = 0 WHERE treatmentBlock_radio IS NULL

-- ** Add a column that contains an indicator of chemotherapy for
-- ** each timestamp.
-- ** This section defines the boundaries of chemotherapy. The logic
-- ** considers all chemotherapy related dates to figure out what 
-- ** duration the chemotherapy covers.
IF OBJECT_ID ('tempdb..#combinedTable_Br_pre6') IS NOT NULL
	DROP TABLE #combinedTable_Br_pre6
IF OBJECT_ID ('tempdb..#TreatmentBlockDates_chemo') IS NOT NULL
	DROP TABLE #TreatmentBlockDates_chemo
SELECT pID7, chemoTreatmentStart, chemoTreatmentEnd INTO #TreatmentBlockDates_chemo
FROM
(
	-- ** Selects all patients that have a chemotherapy and presents
	-- ** the start and end date of those treatments. Patients can be
	-- ** associated with more than one duration of chemotherapy.
	-- ** Any overlaps are combined.
	--
	-- ** Selects non-overlapping estimated chemotherapies.
	SELECT pID6 AS pID7, THE_chemoTreatmentStart AS chemoTreatmentStart, THE_chemoTreatmentEnd AS chemoTreatmentEnd
	FROM
	(
		-- ** Merges overlapping chemotherapy durations.
		SELECT pID4 AS pID6, prevEndOverlapsThisStart,
			chemoTreatmentStart AS THE_chemoTreatmentStart,
			(CASE
				WHEN prevEndOverlapsThisStart = 0 AND nextStartOverlapsThisEnd = 1 THEN
					LEAD(chemoTreatmentEnd) OVER(PARTITION BY pID4 ORDER BY chemoTreatmentStart)
				ELSE chemoTreatmentEnd
			END) AS THE_chemoTreatmentEnd
		FROM
		(
			-- ** Finds which selected chemotherapies durations overlap.
			SELECT *,
				(CASE
					WHEN (LAG(chemoTreatmentEnd) OVER(PARTITION BY pID4 ORDER BY chemoTreatmentStart)) > chemoTreatmentStart THEN
						-- ...then the previous chemotherapy overlaps.
						1
					ELSE 0
				END) AS prevEndOverlapsThisStart,
				(CASE
					WHEN (LEAD(chemoTreatmentStart) OVER(PARTITION BY pID4 ORDER BY chemoTreatmentStart)) < chemoTreatmentEnd THEN
						-- ...then the subsequent chemotherapy overlaps.
						1
					ELSE 0
				END) AS nextStartOverlapsThisEnd
			FROM
			(
				-- ** Finds the minimum start date for common end dates.
				SELECT DISTINCT pID3 AS pID4, MIN(chemoTreatmentStart) OVER(PARTITION BY pID3, chemoTreatmentEnd) AS chemoTreatmentStart,
						chemoTreatmentEnd
				FROM		
				(	
					-- ** Finds the maximum end date for common start dates.
					SELECT DISTINCT pID AS pID3, chemoTreatmentStart,
								MAX(chemoTreatmentEnd) OVER(PARTITION BY pID, chemoTreatmentStart) AS chemoTreatmentEnd
					FROM
					(
						-- ** Selects all rows that have a timestamp relating to chemotherapy.
						SELECT DISTINCT pID, ts, cycleStartDate, drugStartDate, regStartDate, regEndDate,
								regDecisionDate, regimenID, regimenDuration,
						(CASE
							WHEN regStartDate IS NOT NULL THEN
								regStartDate
							WHEN (regStartDate IS NULL AND cycleStartDate IS NOT NULL) THEN
								cycleStartDate
							WHEN (regStartDate IS NULL AND cycleStartDate IS NULL AND drugStartDate IS NOT NULL) THEN
								drugStartDate
							ELSE
								NULL
						END) AS chemoTreatmentStart,
						(CASE
							WHEN regEndDate IS NOT NULL THEN
								regEndDate
							WHEN regEndDate IS NULL THEN
								DATEADD(d, expDurationOfCycle, maxCycleStart)
							ELSE
								NULL
						END) AS chemoTreatmentEnd
						FROM
							#combinedTable_Br_pre5
							AS t1
						LEFT OUTER JOIN
							(
							-- ** I need this select to find the final cycle of a regimen. It will be used
							-- ** with the expected duration of the cycle to infer the end of a regimen.
							-- ** Sometimes, this will lead to overlapping with subsequent start dates becase
							-- ** a cycle was stopped sooner than expected.
							SELECT pID AS pID2, regimenID AS regimenID2, MAX(cycleStartDate) AS maxCycleStart
							FROM #combinedTable_Br_pre5
							GROUP BY pID, regimenID
							) t2
						ON t1.pID = t2.pID2 AND t1.regimenID = t2.regimenID2
						WHERE cycleStartDate IS NOT NULL OR drugStartDate IS NOT NULL OR regStartDate IS NOT NULL
									OR regEndDate IS NOT NULL OR regDecisionDate IS NOT NULL
					) t3
					WHERE chemoTreatmentEnd IS NOT NULL
					GROUP BY pID, chemoTreatmentStart, chemoTreatmentEnd
				) t4
				GROUP BY pID3, chemoTreatmentEnd, chemoTreatmentStart
			) t5
		) t6
		WHERE NOT (prevEndOverlapsThisStart = 1 AND nextStartOverlapsThisEnd = 1)
	) t7
	WHERE prevEndOverlapsThisStart != 1
) t8
SELECT * INTO #combinedTable_Br_pre6
FROM
#combinedTable_Br_pre5 AS t10
LEFT OUTER JOIN
	(
	-- ** Select and flag timestamps from combined colum 
	-- ** that are within a chemotherapy duration.
	SELECT DISTINCT rowID8, 1 AS treatmentBlock_chemo
	FROM
		(
		-- ** Selects identifiers from the combined table.
		SELECT rowID AS rowID8, pID AS pID8, ts AS ts8
		FROM
		#combinedTable_Br_pre5
		) t8
	JOIN
		#TreatmentBlockDates_chemo AS t9
	ON t8.pID8 = t9.pID7
	WHERE ts8 BETWEEN chemoTreatmentStart AND chemoTreatmentEnd		
	) t11
ON t10.rowID = t11.rowID8
ORDER BY pID, ts
ALTER TABLE #combinedTable_Br_pre6 DROP COLUMN rowID8
UPDATE #combinedTable_Br_pre6 SET treatmentBlock_chemo = 0 WHERE treatmentBlock_chemo IS NULL

end --

-- Show final output.
SELECT * FROM #combinedTable_Br_pre6 ORDER BY pID, ts

-- *******************************************************************
-- ** Create the final flat tables. **
-- *******************************************************************
begin --
SELECT * INTO demogTable_Br FROM #demogTable_Br
SELECT * INTO consultTable_Br FROM #consultTable_Br
SELECT * INTO annotationsTable_Br FROM #annotationsTable_Br
SELECT * INTO outpatientTable_Br FROM #outpatientTable_Br
SELECT * INTO admissionsTable_Br FROM #admissionsTable_Br
SELECT * INTO radioTable_Br FROM #radioTable_Br
SELECT * INTO radioExTable_Br FROM #radioExTable_Br
SELECT * INTO wardstaysTable_Br FROM #wardstaysTable_Br
SELECT * INTO chemoTable_Br FROM #chemoTable_Br
SELECT * INTO surgTable_Br FROM #surgTable_Br
SELECT * INTO investigationTable_Br FROM #investigationTable_Br
SELECT * INTO diagnosisTable_Br FROM #diagnosisTable_Br
SELECT * INTO MDTrevTable_Br FROM #MDTrevTable_Br
SELECT * INTO deathDate_Br FROM #deathDate_Br
SELECT * INTO oneColWorsening_Br FROM #oneColWorsening_Br
SELECT * INTO recurrences_Br FROM #recurrences_Br
SELECT * INTO TreatmentBlockDates_radio FROM #TreatmentBlockDates_radio
SELECT * INTO TreatmentBlockDates_chemo FROM #TreatmentBlockDates_chemo
SELECT * INTO combinedTable_Br FROM #combinedTable_Br_pre6

end --




END