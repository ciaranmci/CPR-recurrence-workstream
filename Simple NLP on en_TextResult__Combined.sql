CREATE PROCEDURE [simpleNLPforCPRproject]
AS
BEGIN
-- **********************************
-- ***** Breast cohort patients *****
-- **********************************

-- ** Prepare some prerequisites. **
begin --
DECLARE @WLbreast varchar(8) = '11003158';
IF OBJECT_ID ('tempdb..#BreastPatients') IS NOT NULL DROP TABLE #BreastPatients;
CREATE TABLE #BreastPatients(pID int);
INSERT INTO #BreastPatients(pID)
SELECT DISTINCT wc_PatientID BreastWatchlistPID
FROM PPMQuery.leeds.Watch
WHERE wc_WatchDefinitionID like @WLbreast
ORDER BY BreastWatchlistPID;


IF OBJECT_ID ('tempdb..#recurrences_Br') IS NOT NULL DROP TABLE #recurrences_Br
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
		WHERE dx_PatientID IN (SELECT * FROM #BreastPatients))
		AND Cohort = 'Breast'
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
IF OBJECT_ID ('tempdb..#oneColWorsening_Br') IS NOT NULL DROP TABLE #oneColWorsening_Br
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

-- ** Prepare the portion of text to be reviewed. **
IF OBJECT_ID ('tempdb..#extractedText') IS NOT NULL DROP TABLE #extractedText
SELECT DISTINCT pID, en_EventDate, leftWasCut
INTO #extractedText
FROM
(
SELECT en_EventID, en_EventDate, en_PatientID, REPLACE(SUBSTRING(en_TextResult, CHARINDEX('CONCLUSION:', en_TextResult), LEN(en_TextResult)), 'CONCLUSION:', 'myCONCLUSION') AS leftWasCut
FROM PPMQuery.leeds.Investigations
WHERE en_TextResult LIKE '%CONCLUSION:%'
AND en_PatientID IN (SELECT * FROM #BreastPatients) ) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier pID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #BreastPatients))) t2
ON t1.en_PatientID = t2.ex_PatientID
JOIN
(SELECT * FROM #recurrences_Br ) t3
ON t2.pID = t3.recurpID
WHERE en_EventDate < '2012-04-13'
ORDER BY pID, en_EventDate

-- ** Compute the indicators of interest. **
-- **********************************
-- ** I'm sure there is a clean way to do the following by creating a list of 
-- ** keywords and their negations, and then evaluating a concatonated character 
-- ** command but I think I will be quicker just hard coding everything.
-- **********************************
begin --
-- ** wflag_metastNOTno ** -- 1
IF OBJECT_ID ('tempdb..#wflag_metastNOTno') IS NOT NULL DROP TABLE #wflag_metastNOTno
SELECT newid() AS key1, pID AS pID1, en_EventDate AS en_EventDate1, * INTO #wflag_metastNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTno = 1
ALTER TABLE #wflag_metastNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTrather ** -- 2
IF OBJECT_ID ('tempdb..#wflag_metastNOTrather') IS NOT NULL DROP TABLE #wflag_metastNOTrather
SELECT newid() AS key2, pID AS pID2, en_EventDate AS en_EventDate2, * INTO #wflag_metastNOTrather FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTrather
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTrather = 1
ALTER TABLE #wflag_metastNOTrather DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTstable ** -- 3
IF OBJECT_ID ('tempdb..#wflag_metastNOTstable') IS NOT NULL DROP TABLE #wflag_metastNOTstable
SELECT newid() AS key3, pID AS pID3, en_EventDate AS en_EventDate3, * INTO #wflag_metastNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTstable = 1
ALTER TABLE #wflag_metastNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTknown ** -- 4
IF OBJECT_ID ('tempdb..#wflag_metastNOTknown') IS NOT NULL DROP TABLE #wflag_metastNOTknown
SELECT newid() AS key4, pID AS pID4, en_EventDate AS en_EventDate4, * INTO #wflag_metastNOTknown FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTknown
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTknown = 1
ALTER TABLE #wflag_metastNOTknown DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTdecrease ** -- 5
IF OBJECT_ID ('tempdb..#wflag_metastNOTdecrease') IS NOT NULL DROP TABLE #wflag_metastNOTdecrease
SELECT newid() AS key5, pID AS pID5, en_EventDate AS en_EventDate5, * INTO #wflag_metastNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTdecrease = 1
ALTER TABLE #wflag_metastNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_recurNOTno ** -- 6
IF OBJECT_ID ('tempdb..#wflag_recurNOTno') IS NOT NULL DROP TABLE #wflag_recurNOTno
SELECT newid() AS key6, pID AS pID6, en_EventDate AS en_EventDate6, * INTO #wflag_recurNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_recurNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%recur%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_recurNOTno = 1
ALTER TABLE #wflag_recurNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTunchanged ** -- 7
IF OBJECT_ID ('tempdb..#wflag_malignanNOTunchanged') IS NOT NULL DROP TABLE #wflag_malignanNOTunchanged
SELECT newid() AS key7, pID AS pID7, en_EventDate AS en_EventDate7, * INTO #wflag_malignanNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTunchanged = 1
ALTER TABLE #wflag_malignanNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTno ** -- 8
IF OBJECT_ID ('tempdb..#wflag_malignanNOTno') IS NOT NULL DROP TABLE #wflag_malignanNOTno
SELECT newid() AS key8, pID AS pID8, en_EventDate AS en_EventDate8, * INTO #wflag_malignanNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTno = 1
ALTER TABLE #wflag_malignanNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_unchangedNOTmalignan ** -- 9
IF OBJECT_ID ('tempdb..#wflag_unchangedNOTmalignan') IS NOT NULL DROP TABLE #wflag_unchangedNOTmalignan
SELECT newid() AS key9, pID AS pID9, en_EventDate AS en_EventDate9, * INTO #wflag_unchangedNOTmalignan FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_unchangedNOTmalignan
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_unchangedNOTmalignan = 1
ALTER TABLE #wflag_unchangedNOTmalignan DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTreduc ** -- 10
IF OBJECT_ID ('tempdb..#wflag_bulkNOTreduc') IS NOT NULL DROP TABLE #wflag_bulkNOTreduc
SELECT newid() AS key10, pID AS pID10, en_EventDate AS en_EventDate10, * INTO #wflag_bulkNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTreduc = 1
ALTER TABLE #wflag_bulkNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTdecrease ** -- 11
IF OBJECT_ID ('tempdb..#wflag_bulkNOTdecrease') IS NOT NULL DROP TABLE #wflag_bulkNOTdecrease
SELECT newid() AS key11, pID AS pID11, en_EventDate AS en_EventDate11, * INTO #wflag_bulkNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTdecrease = 1
ALTER TABLE #wflag_bulkNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTreduc ** -- 12
IF OBJECT_ID ('tempdb..#wflag_massNOTreduc') IS NOT NULL DROP TABLE #wflag_massNOTreduc
SELECT newid() AS key12, pID AS pID12, en_EventDate AS en_EventDate12, * INTO #wflag_massNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTreduc = 1
ALTER TABLE #wflag_massNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTdecrease ** -- 13
IF OBJECT_ID ('tempdb..#wflag_massNOTdecrease') IS NOT NULL DROP TABLE #wflag_massNOTdecrease
SELECT newid() AS key13, pID AS pID13, en_EventDate AS en_EventDate13, * INTO  #wflag_massNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTdecrease = 1
ALTER TABLE #wflag_massNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTunchanged ** -- 14
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTunchanged') IS NOT NULL DROP TABLE #wflag_diseaseNOTunchanged
SELECT newid() AS key14, pID AS pID14, en_EventDate AS en_EventDate14, * INTO #wflag_diseaseNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTunchanged = 1
ALTER TABLE #wflag_diseaseNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTstable ** -- 15
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTstable') IS NOT NULL DROP TABLE #wflag_diseaseNOTstable
SELECT newid() AS key15, pID AS pID15, en_EventDate AS en_EventDate15, * INTO #wflag_diseaseNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTstable = 1
ALTER TABLE #wflag_diseaseNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_resolvNOTdisease ** -- 16
IF OBJECT_ID ('tempdb..#wflag_resolvNOTdisease') IS NOT NULL DROP TABLE #wflag_resolvNOTdisease
SELECT newid() AS key16, pID AS pID16, en_EventDate AS en_EventDate16, * INTO #wflag_resolvNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_resolvNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_resolvNOTdisease = 1
ALTER TABLE #wflag_resolvNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_stableNOTdisease ** -- 17
IF OBJECT_ID ('tempdb..#wflag_stableNOTdisease') IS NOT NULL DROP TABLE #wflag_stableNOTdisease
SELECT newid() AS key17, pID AS pID17, en_EventDate AS en_EventDate17, * INTO #wflag_stableNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_stableNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_stableNOTdisease = 1
ALTER TABLE #wflag_stableNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_responseNOTdisease ** -- 18
IF OBJECT_ID ('tempdb..#wflag_responseNOTdisease') IS NOT NULL DROP TABLE #wflag_responseNOTdisease
SELECT newid() AS key18, pID AS pID18, en_EventDate AS en_EventDate18, * INTO #wflag_responseNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_responseNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_responseNOTdisease = 1
ALTER TABLE #wflag_responseNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTreduc ** -- 19
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTreduc') IS NOT NULL DROP TABLE #wflag_diseaseNOTreduc
SELECT newid() AS key19, pID as pID19, en_EventDate AS en_EventDate19, * INTO #wflag_diseaseNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTreduc = 1
ALTER TABLE #wflag_diseaseNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTpaget ** -- 20
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTpaget') IS NOT NULL DROP TABLE #wflag_diseaseNOTpaget
SELECT newid() AS key20, pID AS pID20, en_EventDate AS en_EventDate20, * INTO #wflag_diseaseNOTpaget FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTpaget
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTpaget = 1
ALTER TABLE #wflag_diseaseNOTpaget DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTdecrease ** -- 21
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTdecrease') IS NOT NULL DROP TABLE #wflag_diseaseNOTdecrease
SELECT newid() AS key21, pID as pID21, en_EventDate AS en_EventDate21, * INTO #wflag_diseaseNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTdecrease = 1
ALTER TABLE #wflag_diseaseNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTno ** -- 22
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTno') IS NOT NULL DROP TABLE #wflag_diseaseNOTno
SELECT newid() AS key22, pID as pID22, en_EventDate AS en_EventDate22, * INTO #wflag_diseaseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTno = 1
ALTER TABLE #wflag_diseaseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTunchanged ** -- 23
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTunchanged') IS NOT NULL DROP TABLE #wflag_carcinomaNOTunchanged
SELECT newid() AS key23, pID AS pID23, en_EventDate AS en_EventDate23, * INTO #wflag_carcinomaNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTunchanged = 1
ALTER TABLE #wflag_carcinomaNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTkeeping ** -- 24
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTkeeping') IS NOT NULL DROP TABLE #wflag_carcinomaNOTkeeping
SELECT newid() AS key24, pID AS pID24, en_EventDate AS en_EventDate24, * INTO #wflag_carcinomaNOTkeeping FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTkeeping
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTkeeping = 1
ALTER TABLE #wflag_carcinomaNOTkeeping DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTno ** -- 25
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTno') IS NOT NULL DROP TABLE #wflag_carcinomaNOTno
SELECT newid() AS key25, pID AS pID25, en_EventDate AS en_EventDate25, * INTO #wflag_carcinomaNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTno = 1
ALTER TABLE #wflag_carcinomaNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_neoplasmNOTno ** -- 26
IF OBJECT_ID ('tempdb..#wflag_neoplasmNOTno') IS NOT NULL DROP TABLE #wflag_neoplasmNOTno
SELECT newid() AS key26, pID AS pID26, en_EventDate AS en_EventDate26, * INTO #wflag_neoplasmNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_neoplasmNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%neoplasm%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_neoplasmNOTno = 1
ALTER TABLE #wflag_neoplasmNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_progressNOTno ** -- 27
IF OBJECT_ID ('tempdb..#wflag_progressNOTno') IS NOT NULL DROP TABLE #wflag_progressNOTno
SELECT newid() AS key27, pID AS pID27, en_EventDate AS en_EventDate27, * INTO #wflag_progressNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_progressNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%progress%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_progressNOTno = 1
ALTER TABLE #wflag_progressNOTno DROp COLUMN pID, en_EventDate

-- ** wflag_deterioratNOTno ** -- 28
IF OBJECT_ID ('tempdb..#wflag_deterioratNOTno') IS NOT NULL DROP TABLE #wflag_deterioratNOTno
SELECT newid() AS key28, pID AS pID28, en_EventDate AS en_EventDate28, * INTO #wflag_deterioratNOTno FROM
( 
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_deterioratNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%deteriorat%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_deterioratNOTno = 1
ALTER TABLE #wflag_deterioratNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_relapseNOTno ** -- 29
IF OBJECT_ID ('tempdb..#wflag_relapseNOTno') IS NOT NULL DROP TABLE #wflag_relapseNOTno
SELECT newid() AS key29, pID AS pID29, en_EventDate AS en_EventDate29, * INTO #wflag_relapseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_relapseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%relapse%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_relapseNOTno = 1 
ALTER TABLE #wflag_relapseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_increaseinvolumeNOTno ** -- 30
IF OBJECT_ID ('tempdb..#wflag_increaseinvolumeNOTno') IS NOT NULL DROP TABLE #wflag_increaseinvolumeNOTno
SELECT newid() AS key30, pID AS pID30, en_EventDate AS en_EventDate30, * INTO #wflag_increaseinvolumeNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_increaseinvolumeNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%increase in volume%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_increaseinvolumeNOTno = 1
ALTER TABLE #wflag_increaseinvolumeNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_effusionNOTincreaseinsize ** -- 31
IF OBJECT_ID ('tempdb..#wflag_effusionNOTincreaseinsize') IS NOT NULL DROP TABLE #wflag_effusionNOTincreaseinsize
SELECT newid() AS key31, pID AS pID31, en_EventDate AS en_EventDate31, * INTO #wflag_effusionNOTincreaseinsize FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_effusionNOTincreaseinsize
	FROM
	(
	SELECT *,
			PATINDEX('%effusion%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_effusionNOTincreaseinsize = 1
ALTER TABLE #wflag_effusionNOTincreaseinsize DROP COLUMN pID, en_EventDate

-- ** wflag_spreadNOTno ** -- 32
IF OBJECT_ID ('tempdb..#wflag_spreadNOTno') IS NOT NULL DROP TABLE #wflag_spreadNOTno
SELECT newid() AS key32, pID AS pID32, en_EventDate AS en_EventDate32, * INTO #wflag_spreadNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_spreadNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%spread%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_spreadNOTno = 1
ALTER TABLE #wflag_spreadNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseANDsecondary ** -- 33
IF OBJECT_ID ('tempdb..#wflag_diseaseANDsecondary') IS NOT NULL DROP TABLE #wflag_diseaseANDsecondary
SELECT newid() AS key33, pID AS pID33, en_EventDate AS en_EventDate33, * INTO #wflag_diseaseANDsecondary FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseANDsecondary
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseANDsecondary = 1
ALTER TABLE #wflag_diseaseANDsecondary DROP COLUMN pID, en_EventDate

-- ** nwflag_stableNOTnot ** -- 34
IF OBJECT_ID ('tempdb..#nwflag_stableNOTnot') IS NOT NULL DROP TABLE #nwflag_stableNOTnot
SELECT newid() AS key34, pID AS pID34, en_EventDate AS en_EventDate34, * INTO #nwflag_stableNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_stableNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%stable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_stableNOTnot = 1
ALTER TABLE #nwflag_stableNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_resolvANDdisease ** -- 35
IF OBJECT_ID ('tempdb..#nwflag_resolvANDdisease') IS NOT NULL DROP TABLE #nwflag_resolvANDdisease
SELECT newid() AS key35, pID AS pID35, en_EventDate AS en_EventDate35, * INTO #nwflag_resolvANDdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_resolvANDdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_resolvANDdisease = 1
ALTER TABLE #nwflag_resolvANDdisease DROP COLUMN pID, en_EventDate

-- ** nwflag_diseaseANDno ** -- 36
IF OBJECT_ID ('tempdb..#nwflag_diseaseANDno') IS NOT NULL DROP TABLE #nwflag_diseaseANDno
SELECT newid() AS key36, pID AS pID36, en_EventDate AS en_EventDate36, * INTO #nwflag_diseaseANDno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_diseaseANDno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_diseaseANDno = 1
ALTER TABLE #nwflag_diseaseANDno DROP COLUMN pID, en_EventDate

-- ** nwflag_noevidenceNOTconclusion ** -- 37
IF OBJECT_ID ('tempdb..#nwflag_noevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_noevidenceNOTconclusion
SELECT newid() AS key37, pID AS pID37, en_EventDate AS en_EventDate37, * INTO #nwflag_noevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_noevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_noevidenceNOTconclusion = 1
ALTER TABLE #nwflag_noevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nodefiniteevidenceNOTconclusion ** -- 38
IF OBJECT_ID ('tempdb..#nwflag_nodefiniteevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_nodefiniteevidenceNOTconclusion
SELECT newid() AS key38, pID AS pID38, en_EventDate AS en_EventDate38, * INTO #nwflag_nodefiniteevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nodefiniteevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no definite evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nodefiniteevidenceNOTconclusion = 1
ALTER TABLE #nwflag_nodefiniteevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nomeasurableNOTno ** -- 39
IF OBJECT_ID ('tempdb..#nwflag_nomeasurableNOTno') IS NOT NULL DROP TABLE #nwflag_nomeasurableNOTno
SELECT newid() AS key39, pID AS pID39, en_EventDate AS en_EventDate39,  * INTO #nwflag_nomeasurableNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nomeasurableNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%no measurable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%respono measurablense%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nomeasurableNOTno = 1
ALTER TABLE #nwflag_nomeasurableNOTno DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTnot ** -- 40
IF OBJECT_ID ('tempdb..#nwflag_responseNOTnot') IS NOT NULL DROP TABLE #nwflag_responseNOTnot
SELECT newid() AS key40, pID AS pID40, en_EventDate AS en_EventDate40, * INTO #nwflag_responseNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTnot = 1
ALTER TABLE #nwflag_responseNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTno ** -- 41
IF OBJECT_ID ('tempdb..#nwflag_responseNOTno') IS NOT NULL DROP TABLE #nwflag_responseNOTno
SELECT newid() AS key41, pID AS pID41, en_EventDate AS en_EventDate41, * INTO #nwflag_responseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTno = 1 
ALTER TABLE #nwflag_responseNOTno DROP COLUMN pID, en_EventDate

-- ** mflag_responseANDmixed ** -- 42
IF OBJECT_ID ('tempdb..#mflag_responseANDmixed') IS NOT NULL DROP TABLE #mflag_responseANDmixed
SELECT newid() AS key42, pID AS pID42, en_EventDate AS en_EventDate42, * INTO #mflag_responseANDmixed FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS mflag_responseANDmixed
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE mflag_responseANDmixed = 1
ALTER TABLE #mflag_responseANDmixed DROP COLUMN pID, en_EventDate
end --

-- ** Bring it all together into #simpleNLP_Br. **
IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'cpr' AND TABLE_NAME = 'simpleNLP_Br')) 
BEGIN DROP TABLE simpleNLP_Br END
SELECT unionKey AS pID, unionpID, unionts AS ts,
		wflag_metastNOTno,
		wflag_metastNOTrather,
		wflag_metastNOTstable,
		wflag_metastNOTknown,
		wflag_metastNOTdecrease,
		wflag_recurNOTno,
		wflag_malignanNOTunchanged,
		wflag_malignanNOTno,
		wflag_unchangedNOTmalignan,
		wflag_bulkNOTreduc,
		wflag_bulkNOTdecrease,
		wflag_massNOTreduc,
		wflag_massNOTdecrease,
		wflag_diseaseNOTunchanged,
		wflag_diseaseNOTstable,
		wflag_resolvNOTdisease,
		wflag_stableNOTdisease,
		wflag_responseNOTdisease,
		wflag_diseaseNOTreduc,
		wflag_diseaseNOTpaget,
		wflag_diseaseNOTdecrease,
		wflag_diseaseNOTno,
		wflag_carcinomaNOTunchanged,
		wflag_carcinomaNOTkeeping,
		wflag_carcinomaNOTno,
		wflag_neoplasmNOTno,
		wflag_progressNOTno,
		wflag_deterioratNOTno,
		wflag_relapseNOTno,
		wflag_increaseinvolumeNOTno,
		wflag_effusionNOTincreaseinsize,
		wflag_spreadNOTno,
		wflag_diseaseANDsecondary,
		nwflag_stableNOTnot,
		nwflag_resolvANDdisease,
		nwflag_diseaseANDno,
		nwflag_noevidenceNOTconclusion,
		nwflag_nodefiniteevidenceNOTconclusion,
		nwflag_nomeasurableNOTno,
		nwflag_responseNOTnot,
		nwflag_responseNOTno,
		mflag_responseANDmixed AS mixedChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 0 IN (wflag_metastNOTno, wflag_metastNOTrather, wflag_metastNOTstable, wflag_metastNOTknown, wflag_metastNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_1,
				(CASE
					WHEN wflag_recurNOTno = 0 THEN
						0
					ELSE 1
				END) +--AS worsenChk_2,
				(CASE
					WHEN 0 IN (wflag_malignanNOTunchanged, wflag_malignanNOTno, wflag_unchangedNOTmalignan) THEN
						0
					ELSE 1
				END) +--AS worsenChk_3,
				(CASE
					WHEN 0 IN (wflag_bulkNOTreduc, wflag_bulkNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_4,
				(CASE
					WHEN 0 IN (wflag_massNOTreduc, wflag_massNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_5,
				(CASE
					WHEN 0 IN (wflag_diseaseNOTunchanged, wflag_diseaseNOTstable, wflag_resolvNOTdisease, wflag_stableNOTdisease, wflag_responseNOTdisease,
								wflag_diseaseNOTreduc, wflag_diseaseNOTpaget, wflag_diseaseNOTdecrease, wflag_diseaseNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_6,
				(CASE
					WHEN 0 IN (wflag_carcinomaNOTunchanged, wflag_carcinomaNOTkeeping, wflag_carcinomaNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_7,
				(CASE
					WHEN 1 IN (wflag_neoplasmNOTno, wflag_progressNOTno, wflag_deterioratNOTno, wflag_relapseNOTno,
								wflag_increaseinvolumeNOTno, wflag_effusionNOTincreaseinsize, wflag_spreadNOTno) THEN
						1
					ELSE 0
				END) +--AS worsenChk_8,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) +--AS worsenChk_9,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) --AS worsenChk_10
			) > 0 THEN 1
			ELSE 0
		END) AS worsenChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 1 IN (nwflag_stableNOTnot, nwflag_resolvANDdisease, nwflag_diseaseANDno, nwflag_noevidenceNOTconclusion, 
								nwflag_nodefiniteevidenceNOTconclusion, nwflag_nomeasurableNOTno) THEN
						1
					ELSE 0
				END) +--AS notWorsenChk_1
				(CASE
					WHEN 1 IN (nwflag_responseNOTnot, nwflag_responseNOTno)  THEN
						1
					ELSE 0
				END) --AS notWorsenChk_2
			) > 0 THEN 1
			ELSE 0
		END) AS notWorsenChk
INTO #simpleNLP_Br
FROM
(
SELECT * FROM( --t42
SELECT * FROM( --t41
SELECT * FROM( --t40
SELECT * FROM( --t39
SELECT * FROM( --t38
SELECT * FROM( --t37
SELECT * FROM( --t36
SELECT * FROM( --t35
SELECT * FROM( --t34
SELECT * FROM( --t33
SELECT * FROM( --t32
SELECT * FROM( --t31
SELECT * FROM( --t30
SELECT * FROM( --t29
SELECT * FROM( --t28
SELECT * FROM( --t27
SELECT * FROM( --t26
SELECT * FROM( --t25
SELECT * FROM( --t24
SELECT * FROM( --t23
SELECT * FROM( --t22
SELECT * FROM( --t21
SELECT * FROM( --t20
SELECT * FROM( --t19
SELECT * FROM( --t18
SELECT * FROM( --t17
SELECT * FROM( --t16
SELECT * FROM( --t15
SELECT * FROM( --t14
SELECT * FROM( --t13
SELECT * FROM( --t12
SELECT * FROM( --t11
SELECT * FROM( --t10
SELECT * FROM( --t9
SELECT * FROM( --t8
SELECT * FROM( --t7
SELECT * FROM( --t6
SELECT * FROM( --t5
SELECT * FROM( --t4
SELECT * FROM( --t3
SELECT * FROM( --t2
SELECT * FROM( --t1
SELECT key1 AS unionKey, pID1 AS unionpID, en_EventDate1 AS unionts FROM #wflag_metastNOTno -- 1
UNION ALL
SELECT key2 AS unionKey, pID2 AS unionpID, en_EventDate2 AS unionts FROM #wflag_metastNOTrather -- 2
UNION ALL
SELECT key3 AS unionKey, pID3 AS unionpID, en_EventDate3 AS unionts FROM #wflag_metastNOTstable-- 3
UNION ALL
SELECT key4 AS unionKey, pID4 AS unionpID, en_EventDate4 AS unionts FROM #wflag_metastNOTknown -- 4
UNION ALL
SELECT key5 AS unionKey, pID5 AS unionpID, en_EventDate5 AS unionts FROM #wflag_metastNOTdecrease -- 5
UNION ALL
SELECT key6 AS unionKey, pID6 AS unionpID, en_EventDate6 AS unionts FROM #wflag_recurNOTno -- 6
UNION ALL
SELECT key7 AS unionKey, pID7 AS unionpID, en_EventDate7 AS unionts FROM #wflag_malignanNOTunchanged -- 7
UNION ALL
SELECT key8 AS unionKey, pID8 AS unionpID, en_EventDate8 AS unionts FROM #wflag_malignanNOTno -- 8
UNION ALL
SELECT key9 AS unionKey, pID9 AS unionpID, en_EventDate9 AS unionts FROM #wflag_unchangedNOTmalignan -- 9
UNION ALL
SELECT key10 AS unionKey, pID10 AS unionpID, en_EventDate10 AS unionts FROM #wflag_bulkNOTreduc -- 10
UNION ALL
SELECT key11 AS unionKey, pID11 AS unionpID, en_EventDate11 AS unionts FROM #wflag_bulkNOTdecrease -- 11
UNION ALL
SELECT key12 AS unionKey, pID12 AS unionpID, en_EventDate12 AS unionts FROM #wflag_massNOTreduc -- 12
UNION ALL
SELECT key13 AS unionKey, pID13 AS unionpID, en_EventDate13 AS unionts FROM #wflag_massNOTdecrease -- 13
UNION ALL
SELECT key14 AS unionKey, pID14 AS unionpID, en_EventDate14 AS unionts FROM #wflag_diseaseNOTunchanged -- 14
UNION ALL
SELECT key15 AS unionKey, pID15 AS unionpID, en_EventDate15 AS unionts FROM #wflag_diseaseNOTstable -- 15
UNION ALL
SELECT key16 AS unionKey, pID16 AS unionpID, en_EventDate16 AS unionts FROM #wflag_resolvNOTdisease -- 16
UNION ALL
SELECT key17 AS unionKey, pID17 AS unionpID, en_EventDate17 AS unionts FROM #wflag_stableNOTdisease -- 17
UNION ALL
SELECT key18 AS unionKey, pID18 AS unionpID, en_EventDate18 AS unionts FROM #wflag_responseNOTdisease -- 18
UNION ALL
SELECT key19 AS unionKey, pID19 AS unionpID, en_EventDate19 AS unionts FROM #wflag_diseaseNOTreduc -- 19
UNION ALL
SELECT key20 AS unionKey, pID20 AS unionpID, en_EventDate20 AS unionts FROM #wflag_diseaseNOTpaget -- 20
UNION ALL
SELECT key21 AS unionKey, pID21 AS unionpID, en_EventDate21 AS unionts FROM #wflag_diseaseNOTdecrease -- 21
UNION ALL
SELECT key22 AS unionKey, pID22 AS unionpID, en_EventDate22 AS unionts FROM #wflag_diseaseNOTno -- 22
UNION ALL
SELECT key23 AS unionKey, pID23 AS unionpID, en_EventDate23 AS unionts FROM #wflag_carcinomaNOTunchanged -- 23
UNION ALL
SELECT key24 AS unionKey, pID24 AS unionpID, en_EventDate24 AS unionts FROM #wflag_carcinomaNOTkeeping -- 24
UNION ALL
SELECT key25 AS unionKey, pID25 AS unionpID, en_EventDate25 AS unionts FROM #wflag_carcinomaNOTno -- 25
UNION ALL
SELECT key26 AS unionKey, pID26 AS unionpID, en_EventDate26 AS unionts FROM #wflag_neoplasmNOTno -- 26
UNION ALL
SELECT key27 AS unionKey, pID27 AS unionpID, en_EventDate27 AS unionts FROM #wflag_progressNOTno -- 27
UNION ALL
SELECT key28 AS unionKey, pID28 AS unionpID, en_EventDate28 AS unionts FROM #wflag_deterioratNOTno -- 28
UNION ALL
SELECT key29 AS unionKey, pID29 AS unionpID, en_EventDate29 AS unionts FROM #wflag_relapseNOTno -- 29
UNION ALL
SELECT key30 AS unionKey, pID30 AS unionpID, en_EventDate30 AS unionts FROM #wflag_increaseinvolumeNOTno -- 30
UNION ALL
SELECT key31 AS unionKey, pID31 AS unionpID, en_EventDate31 AS unionts FROM #wflag_effusionNOTincreaseinsize -- 31
UNION ALL
SELECT key32 AS unionKey, pID32 AS unionpID, en_EventDate32 AS unionts FROM #wflag_spreadNOTno -- 32
UNION ALL
SELECT key33 AS unionKey, pID33 AS unionpID, en_EventDate33 AS unionts FROM #wflag_diseaseANDsecondary -- 33
UNION ALL
SELECT key34 AS unionKey, pID34 AS unionpID, en_EventDate34 AS unionts FROM #nwflag_stableNOTnot -- 34
UNION ALL
SELECT key35 AS unionKey, pID35 AS unionpID, en_EventDate35 AS unionts FROM #nwflag_resolvANDdisease -- 35
UNION ALL
SELECT key36 AS unionKey, pID36 AS unionpID, en_EventDate36 AS unionts FROM #nwflag_diseaseANDno -- 36
UNION ALL
SELECT key37 AS unionKey, pID37 AS unionpID, en_EventDate37 AS unionts FROM #nwflag_noevidenceNOTconclusion -- 37
UNION ALL
SELECT key38 AS unionKey, pID38 AS unionpID, en_EventDate38 AS unionts FROM #nwflag_nodefiniteevidenceNOTconclusion -- 38
UNION ALL
SELECT key39 AS unionKey, pID39 AS unionpID, en_EventDate39 AS unionts FROM #nwflag_nomeasurableNOTno -- 39
UNION ALL
SELECT key40 AS unionKey, pID40 AS unionpID, en_EventDate40 AS unionts FROM #nwflag_responseNOTnot -- 40
UNION ALL
SELECT key41 AS unionKey, pID41 AS unionpID, en_EventDate41 AS unionts FROM #nwflag_responseNOTno -- 41
UNION ALL
SELECT key42 AS unionKey, pID42 AS unionpID, en_EventDate42 AS unionts FROM #mflag_responseANDmixed -- 42
) t1
LEFT OUTER JOIN
(SELECT key1, wflag_metastNOTno FROM #wflag_metastNOTno) t
ON unionKey = t.key1
) t2
LEFT OUTER JOIN
(SELECT key2, wflag_metastNOTrather FROM #wflag_metastNOTrather) t
ON unionKey = t.key2
) t3
LEFT OUTER JOIN
(SELECT key3, wflag_metastNOTstable FROM #wflag_metastNOTstable) t
ON unionKey = t.key3
) t4
LEFT OUTER JOIN
(SELECT key4, wflag_metastNOTknown FROM #wflag_metastNOTknown) t
ON unionKey = t.key4
) t5
LEFT OUTER JOIN
(SELECT key5, wflag_metastNOTdecrease FROM #wflag_metastNOTdecrease) t
ON unionKey = t.key5
) t6
LEFT OUTER JOIN
(SELECT key6, wflag_recurNOTno FROM #wflag_recurNOTno) t
ON unionKey = t.key6
) t7
LEFT OUTER JOIN
(SELECT key7, wflag_malignanNOTunchanged FROM #wflag_malignanNOTunchanged) t
ON unionKey = t.key7
) t8
LEFT OUTER JOIN
(SELECT key8, wflag_malignanNOTno FROM #wflag_malignanNOTno) t
ON unionKey = t.key8
) t9
LEFT OUTER JOIN
(SELECT key9, wflag_unchangedNOTmalignan FROM #wflag_unchangedNOTmalignan) t
ON unionKey = t.key9
) t10
LEFT OUTER JOIN
(SELECT key10, wflag_bulkNOTreduc FROM #wflag_bulkNOTreduc) t
ON unionKey = t.key10
) t11
LEFT OUTER JOIN
(SELECT key11, wflag_bulkNOTdecrease FROM #wflag_bulkNOTdecrease) t
ON unionKey = t.key11
) t12
LEFT OUTER JOIN
(SELECT key12, wflag_massNOTreduc FROM #wflag_massNOTreduc) t
ON unionKey = t.key12
) t13
LEFT OUTER JOIN
(SELECT key13, wflag_massNOTdecrease FROM #wflag_massNOTdecrease) t
ON unionKey = t.key13
) t14
LEFT OUTER JOIN
(SELECT key14, wflag_diseaseNOTunchanged FROM #wflag_diseaseNOTunchanged) t
ON unionKey = t.key14
) t15
LEFT OUTER JOIN
(SELECT key15, wflag_diseaseNOTstable FROM #wflag_diseaseNOTstable) t
ON unionKey = t.key15
) t16
LEFT OUTER JOIN
(SELECT key16, wflag_resolvNOTdisease FROM #wflag_resolvNOTdisease) t
ON unionKey = t.key16
) t17
LEFT OUTER JOIN
(SELECT key17, wflag_stableNOTdisease FROM #wflag_stableNOTdisease) t
ON unionKey = t.key17
) t18
LEFT OUTER JOIN
(SELECT key18, wflag_responseNOTdisease FROM #wflag_responseNOTdisease) t
ON unionKey = t.key18
) t19
LEFT OUTER JOIN
(SELECT key19, wflag_diseaseNOTreduc FROM #wflag_diseaseNOTreduc) t
ON unionKey = t.key19
) t20
LEFT OUTER JOIN
(SELECT key20, wflag_diseaseNOTpaget FROM #wflag_diseaseNOTpaget) t
ON unionKey = t.key20
) t21
LEFT OUTER JOIN
(SELECT key21, wflag_diseaseNOTdecrease FROM #wflag_diseaseNOTdecrease) t
ON unionKey = t.key21
) t22
LEFT OUTER JOIN
(SELECT key22, wflag_diseaseNOTno FROM #wflag_diseaseNOTno) t
ON unionKey = t.key22
) t23
LEFT OUTER JOIN
(SELECT key23, wflag_carcinomaNOTunchanged FROM #wflag_carcinomaNOTunchanged) t
ON unionKey = t.key23
) t24
LEFT OUTER JOIN
(SELECT key24, wflag_carcinomaNOTkeeping FROM #wflag_carcinomaNOTkeeping) t
ON unionKey = t.key24
) t25
LEFT OUTER JOIN
(SELECT key25, wflag_carcinomaNOTno FROM #wflag_carcinomaNOTno) t
ON unionKey = t.key25
) t26
LEFT OUTER JOIN
(SELECT key26, wflag_neoplasmNOTno FROM #wflag_neoplasmNOTno) t
ON unionKey = t.key26
) t27
LEFT OUTER JOIN
(SELECT key27, wflag_progressNOTno FROM #wflag_progressNOTno) t
ON unionKey = t.key27
) t28
LEFT OUTER JOIN
(SELECT key28, wflag_deterioratNOTno FROM #wflag_deterioratNOTno) t
ON unionKey = t.key28
) t29
LEFT OUTER JOIN
(SELECT key29, wflag_relapseNOTno FROM #wflag_relapseNOTno) t
ON unionKey = t.key29
) t30
LEFT OUTER JOIN
(SELECT key30, wflag_increaseinvolumeNOTno FROM #wflag_increaseinvolumeNOTno) t
ON unionKey = t.key30
) t31
LEFT OUTER JOIN
(SELECT key31, wflag_effusionNOTincreaseinsize FROM #wflag_effusionNOTincreaseinsize) t
ON unionKey = t.key31
) t32
LEFT OUTER JOIN
(SELECT key32, wflag_spreadNOTno FROM #wflag_spreadNOTno) t
ON unionKey = t.key32
) t33
LEFT OUTER JOIN
(SELECT key33, wflag_diseaseANDsecondary FROM #wflag_diseaseANDsecondary) t
ON unionKey = t.key33
) t34
LEFT OUTER JOIN
(SELECT key34, nwflag_stableNOTnot FROM #nwflag_stableNOTnot) t
ON unionKey = t.key34
) t35
LEFT OUTER JOIN
(SELECT key35, nwflag_resolvANDdisease FROM #nwflag_resolvANDdisease) t
ON unionKey = t.key35
) t36
LEFT OUTER JOIN
(SELECT key36, nwflag_diseaseANDno FROM #nwflag_diseaseANDno) t
ON unionKey = t.key36
) t37
LEFT OUTER JOIN
(SELECT key37, nwflag_noevidenceNOTconclusion FROM #nwflag_noevidenceNOTconclusion) t
ON unionKey = t.key37
) t38
LEFT OUTER JOIN
(SELECT key38, nwflag_nodefiniteevidenceNOTconclusion FROM #nwflag_nodefiniteevidenceNOTconclusion) t
ON unionKey = t.key38
) t39
LEFT OUTER JOIN
(SELECT key39, nwflag_nomeasurableNOTno FROM #nwflag_nomeasurableNOTno) t
ON unionKey = t.key39
) t40
LEFT OUTER JOIN
(SELECT key40, nwflag_responseNOTnot FROM #nwflag_responseNOTnot) t
ON unionKey = t.key40
) t41
LEFT OUTER JOIN
(SELECT key41, nwflag_responseNOTno FROM #nwflag_responseNOTno) t
ON unionKey = t.key41
) t42
LEFT OUTER JOIN
(SELECT key42, mflag_responseANDmixed FROM #mflag_responseANDmixed) t
ON unionKey = t.key42
) t43
-- ** Change NULL to zero. **
begin --
UPDATE #simpleNLP_Br SET wflag_metastNOTno = 0 WHERE wflag_metastNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_metastNOTrather = 0 WHERE wflag_metastNOTrather IS NULL
UPDATE #simpleNLP_Br SET wflag_metastNOTstable = 0 WHERE wflag_metastNOTstable IS NULL
UPDATE #simpleNLP_Br SET wflag_metastNOTknown = 0 WHERE wflag_metastNOTknown IS NULL
UPDATE #simpleNLP_Br SET wflag_metastNOTdecrease = 0 WHERE wflag_metastNOTdecrease IS NULL
UPDATE #simpleNLP_Br SET wflag_recurNOTno = 0 WHERE wflag_recurNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_malignanNOTunchanged = 0 WHERE wflag_malignanNOTunchanged IS NULL
UPDATE #simpleNLP_Br SET wflag_malignanNOTno = 0 WHERE wflag_malignanNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_unchangedNOTmalignan = 0 WHERE wflag_unchangedNOTmalignan IS NULL
UPDATE #simpleNLP_Br SET wflag_bulkNOTreduc = 0 WHERE wflag_bulkNOTreduc IS NULL
UPDATE #simpleNLP_Br SET wflag_bulkNOTdecrease = 0 WHERE wflag_bulkNOTdecrease IS NULL
UPDATE #simpleNLP_Br SET wflag_massNOTreduc = 0 WHERE wflag_massNOTreduc IS NULL
UPDATE #simpleNLP_Br SET wflag_massNOTdecrease = 0 WHERE wflag_massNOTdecrease IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTunchanged = 0 WHERE wflag_diseaseNOTunchanged IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTstable = 0 WHERE wflag_diseaseNOTstable IS NULL
UPDATE #simpleNLP_Br SET wflag_resolvNOTdisease = 0 WHERE wflag_resolvNOTdisease IS NULL
UPDATE #simpleNLP_Br SET wflag_stableNOTdisease = 0 WHERE wflag_stableNOTdisease IS NULL
UPDATE #simpleNLP_Br SET wflag_responseNOTdisease = 0 WHERE wflag_responseNOTdisease IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTreduc = 0 WHERE wflag_diseaseNOTreduc IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTpaget = 0 WHERE wflag_diseaseNOTpaget IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTdecrease = 0 WHERE wflag_diseaseNOTdecrease IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseNOTno = 0 WHERE wflag_diseaseNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_carcinomaNOTunchanged = 0 WHERE wflag_carcinomaNOTunchanged IS NULL
UPDATE #simpleNLP_Br SET wflag_carcinomaNOTkeeping = 0 WHERE wflag_carcinomaNOTkeeping IS NULL
UPDATE #simpleNLP_Br SET wflag_carcinomaNOTno = 0 WHERE wflag_carcinomaNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_neoplasmNOTno = 0 WHERE wflag_neoplasmNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_progressNOTno = 0 WHERE wflag_progressNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_deterioratNOTno = 0 WHERE wflag_deterioratNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_relapseNOTno = 0 WHERE wflag_relapseNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_increaseinvolumeNOTno = 0 WHERE wflag_increaseinvolumeNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_effusionNOTincreaseinsize = 0 WHERE wflag_effusionNOTincreaseinsize IS NULL
UPDATE #simpleNLP_Br SET wflag_spreadNOTno = 0 WHERE wflag_spreadNOTno IS NULL
UPDATE #simpleNLP_Br SET wflag_diseaseANDsecondary = 0 WHERE wflag_diseaseANDsecondary IS NULL
UPDATE #simpleNLP_Br SET nwflag_stableNOTnot = 0 WHERE nwflag_stableNOTnot IS NULL
UPDATE #simpleNLP_Br SET nwflag_resolvANDdisease = 0 WHERE nwflag_resolvANDdisease IS NULL
UPDATE #simpleNLP_Br SET nwflag_diseaseANDno = 0 WHERE nwflag_diseaseANDno IS NULL
UPDATE #simpleNLP_Br SET nwflag_noevidenceNOTconclusion = 0 WHERE nwflag_noevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_Br SET nwflag_nodefiniteevidenceNOTconclusion = 0 WHERE nwflag_nodefiniteevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_Br SET nwflag_nomeasurableNOTno = 0 WHERE nwflag_nomeasurableNOTno IS NULL
UPDATE #simpleNLP_Br SET nwflag_responseNOTnot = 0 WHERE nwflag_responseNOTnot IS NULL
UPDATE #simpleNLP_Br SET nwflag_responseNOTno = 0 WHERE nwflag_responseNOTno IS NULL
UPDATE #simpleNLP_Br SET mixedChk = 0 WHERE mixedChk IS NULL
end --


-- ***********************************
-- ***** Ovarian cohort patients *****
-- ***********************************

-- ** Prepare some prerequisites. **
begin --
DECLARE @WLovarian varchar(8) = '11003196';
IF OBJECT_ID ('tempdb..#OvarianPatients') IS NOT NULL DROP TABLE #OvarianPatients;
CREATE TABLE #OvarianPatients(pID int);
INSERT INTO #OvarianPatients(pID)
SELECT DISTINCT wc_PatientID OvarianWatchlistPID
FROM PPMQuery.leeds.Watch
WHERE wc_WatchDefinitionID like @WLovarian
ORDER BY OvarianWatchlistPID;

IF OBJECT_ID ('tempdb..#recurrences_Ov') IS NOT NULL DROP TABLE #recurrences_Ov
CREATE TABLE #recurrences_Ov(
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
INSERT INTO #recurrences_Ov(
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
		WHERE dx_PatientID IN (SELECT * FROM #OvarianPatients))
		AND Cohort = 'Ovarian'
ORDER BY recurpID
-- This table is initially constructed without an uniqueidentifier
-- because of issues with duplicates in the ACNRes table. I add
-- it now.
ALTER TABLE #recurrences_Ov ADD recurIDkey uniqueidentifier
UPDATE #recurrences_Ov SET recurIDkey = newid()
-- SELECT * FROM #recurrences_Ov ORDER BY recurpID

-- ** worsening **
-- ** This table collates all progression and recurrences (hereadter 
-- ** called "worsening") into one column.
IF OBJECT_ID ('tempdb..#oneColWorsening_Ov') IS NOT NULL DROP TABLE #oneColWorsening_Ov
SELECT * INTO #oneColWorsening_Ov
FROM(
	SELECT newid() worsenIDkey, recurpID worsenpID, prevWorsenCnt, worseningDate, DOB, CAST(FLOOR(DATEDIFF(DAY, DOB, worseningDate)/(365.4*5)) AS real) AS ageBandAtWorseningDate
	FROM #recurrences_Ov
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
UPDATE #oneColWorsening_Ov 
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
UPDATE #oneColWorsening_Ov SET ageBandAtWorseningDate = 17 WHERE ageBandAtWorseningDate > 17
-- SELECT * FROM #oneColWorsening_Ov ORDER BY worsenpID, worseningDate
end --

-- ** Prepare the portion of text to be reviewed. **
IF OBJECT_ID ('tempdb..#extractedText') IS NOT NULL DROP TABLE #extractedText
SELECT DISTINCT pID, en_EventDate, leftWasCut
INTO #extractedText
FROM
(
SELECT en_EventID, en_EventDate, en_PatientID, REPLACE(SUBSTRING(en_TextResult, CHARINDEX('CONCLUSION:', en_TextResult), LEN(en_TextResult)), 'CONCLUSION:', 'myCONCLUSION') AS leftWasCut
FROM PPMQuery.leeds.Investigations
WHERE en_TextResult LIKE '%CONCLUSION:%'
AND en_PatientID IN (SELECT * FROM #OvarianPatients) ) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier pID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #OvarianPatients))) t2
ON t1.en_PatientID = t2.ex_PatientID
JOIN
(SELECT * FROM #recurrences_Ov ) t3
ON t2.pID = t3.recurpID
WHERE en_EventDate < '2012-04-13'
ORDER BY pID, en_EventDate

-- ** Compute the indicators of interest. **
-- **********************************
-- ** I'm sure there is a clean way to do the following by creating a list of 
-- ** keywords and their negations, and then evaluating a concatonated character 
-- ** command but I think I will be quicker just hard coding everything.
-- **********************************
begin --
-- ** wflag_metastNOTno ** -- 1
IF OBJECT_ID ('tempdb..#wflag_metastNOTno') IS NOT NULL DROP TABLE #wflag_metastNOTno
SELECT newid() AS key1, pID AS pID1, en_EventDate AS en_EventDate1, * INTO #wflag_metastNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTno = 1
ALTER TABLE #wflag_metastNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTrather ** -- 2
IF OBJECT_ID ('tempdb..#wflag_metastNOTrather') IS NOT NULL DROP TABLE #wflag_metastNOTrather
SELECT newid() AS key2, pID AS pID2, en_EventDate AS en_EventDate2, * INTO #wflag_metastNOTrather FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTrather
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTrather = 1
ALTER TABLE #wflag_metastNOTrather DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTstable ** -- 3
IF OBJECT_ID ('tempdb..#wflag_metastNOTstable') IS NOT NULL DROP TABLE #wflag_metastNOTstable
SELECT newid() AS key3, pID AS pID3, en_EventDate AS en_EventDate3, * INTO #wflag_metastNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTstable = 1
ALTER TABLE #wflag_metastNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTknown ** -- 4
IF OBJECT_ID ('tempdb..#wflag_metastNOTknown') IS NOT NULL DROP TABLE #wflag_metastNOTknown
SELECT newid() AS key4, pID AS pID4, en_EventDate AS en_EventDate4, * INTO #wflag_metastNOTknown FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTknown
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTknown = 1
ALTER TABLE #wflag_metastNOTknown DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTdecrease ** -- 5
IF OBJECT_ID ('tempdb..#wflag_metastNOTdecrease') IS NOT NULL DROP TABLE #wflag_metastNOTdecrease
SELECT newid() AS key5, pID AS pID5, en_EventDate AS en_EventDate5, * INTO #wflag_metastNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTdecrease = 1
ALTER TABLE #wflag_metastNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_recurNOTno ** -- 6
IF OBJECT_ID ('tempdb..#wflag_recurNOTno') IS NOT NULL DROP TABLE #wflag_recurNOTno
SELECT newid() AS key6, pID AS pID6, en_EventDate AS en_EventDate6, * INTO #wflag_recurNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_recurNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%recur%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_recurNOTno = 1
ALTER TABLE #wflag_recurNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTunchanged ** -- 7
IF OBJECT_ID ('tempdb..#wflag_malignanNOTunchanged') IS NOT NULL DROP TABLE #wflag_malignanNOTunchanged
SELECT newid() AS key7, pID AS pID7, en_EventDate AS en_EventDate7, * INTO #wflag_malignanNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTunchanged = 1
ALTER TABLE #wflag_malignanNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTno ** -- 8
IF OBJECT_ID ('tempdb..#wflag_malignanNOTno') IS NOT NULL DROP TABLE #wflag_malignanNOTno
SELECT newid() AS key8, pID AS pID8, en_EventDate AS en_EventDate8, * INTO #wflag_malignanNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTno = 1
ALTER TABLE #wflag_malignanNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_unchangedNOTmalignan ** -- 9
IF OBJECT_ID ('tempdb..#wflag_unchangedNOTmalignan') IS NOT NULL DROP TABLE #wflag_unchangedNOTmalignan
SELECT newid() AS key9, pID AS pID9, en_EventDate AS en_EventDate9, * INTO #wflag_unchangedNOTmalignan FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_unchangedNOTmalignan
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_unchangedNOTmalignan = 1
ALTER TABLE #wflag_unchangedNOTmalignan DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTreduc ** -- 10
IF OBJECT_ID ('tempdb..#wflag_bulkNOTreduc') IS NOT NULL DROP TABLE #wflag_bulkNOTreduc
SELECT newid() AS key10, pID AS pID10, en_EventDate AS en_EventDate10, * INTO #wflag_bulkNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTreduc = 1
ALTER TABLE #wflag_bulkNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTdecrease ** -- 11
IF OBJECT_ID ('tempdb..#wflag_bulkNOTdecrease') IS NOT NULL DROP TABLE #wflag_bulkNOTdecrease
SELECT newid() AS key11, pID AS pID11, en_EventDate AS en_EventDate11, * INTO #wflag_bulkNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTdecrease = 1
ALTER TABLE #wflag_bulkNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTreduc ** -- 12
IF OBJECT_ID ('tempdb..#wflag_massNOTreduc') IS NOT NULL DROP TABLE #wflag_massNOTreduc
SELECT newid() AS key12, pID AS pID12, en_EventDate AS en_EventDate12, * INTO #wflag_massNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTreduc = 1
ALTER TABLE #wflag_massNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTdecrease ** -- 13
IF OBJECT_ID ('tempdb..#wflag_massNOTdecrease') IS NOT NULL DROP TABLE #wflag_massNOTdecrease
SELECT newid() AS key13, pID AS pID13, en_EventDate AS en_EventDate13, * INTO  #wflag_massNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTdecrease = 1
ALTER TABLE #wflag_massNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTunchanged ** -- 14
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTunchanged') IS NOT NULL DROP TABLE #wflag_diseaseNOTunchanged
SELECT newid() AS key14, pID AS pID14, en_EventDate AS en_EventDate14, * INTO #wflag_diseaseNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTunchanged = 1
ALTER TABLE #wflag_diseaseNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTstable ** -- 15
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTstable') IS NOT NULL DROP TABLE #wflag_diseaseNOTstable
SELECT newid() AS key15, pID AS pID15, en_EventDate AS en_EventDate15, * INTO #wflag_diseaseNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTstable = 1
ALTER TABLE #wflag_diseaseNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_resolvNOTdisease ** -- 16
IF OBJECT_ID ('tempdb..#wflag_resolvNOTdisease') IS NOT NULL DROP TABLE #wflag_resolvNOTdisease
SELECT newid() AS key16, pID AS pID16, en_EventDate AS en_EventDate16, * INTO #wflag_resolvNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_resolvNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_resolvNOTdisease = 1
ALTER TABLE #wflag_resolvNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_stableNOTdisease ** -- 17
IF OBJECT_ID ('tempdb..#wflag_stableNOTdisease') IS NOT NULL DROP TABLE #wflag_stableNOTdisease
SELECT newid() AS key17, pID AS pID17, en_EventDate AS en_EventDate17, * INTO #wflag_stableNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_stableNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_stableNOTdisease = 1
ALTER TABLE #wflag_stableNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_responseNOTdisease ** -- 18
IF OBJECT_ID ('tempdb..#wflag_responseNOTdisease') IS NOT NULL DROP TABLE #wflag_responseNOTdisease
SELECT newid() AS key18, pID AS pID18, en_EventDate AS en_EventDate18, * INTO #wflag_responseNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_responseNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_responseNOTdisease = 1
ALTER TABLE #wflag_responseNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTreduc ** -- 19
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTreduc') IS NOT NULL DROP TABLE #wflag_diseaseNOTreduc
SELECT newid() AS key19, pID as pID19, en_EventDate AS en_EventDate19, * INTO #wflag_diseaseNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTreduc = 1
ALTER TABLE #wflag_diseaseNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTpaget ** -- 20
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTpaget') IS NOT NULL DROP TABLE #wflag_diseaseNOTpaget
SELECT newid() AS key20, pID AS pID20, en_EventDate AS en_EventDate20, * INTO #wflag_diseaseNOTpaget FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTpaget
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTpaget = 1
ALTER TABLE #wflag_diseaseNOTpaget DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTdecrease ** -- 21
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTdecrease') IS NOT NULL DROP TABLE #wflag_diseaseNOTdecrease
SELECT newid() AS key21, pID as pID21, en_EventDate AS en_EventDate21, * INTO #wflag_diseaseNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTdecrease = 1
ALTER TABLE #wflag_diseaseNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTno ** -- 22
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTno') IS NOT NULL DROP TABLE #wflag_diseaseNOTno
SELECT newid() AS key22, pID as pID22, en_EventDate AS en_EventDate22, * INTO #wflag_diseaseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTno = 1
ALTER TABLE #wflag_diseaseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTunchanged ** -- 23
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTunchanged') IS NOT NULL DROP TABLE #wflag_carcinomaNOTunchanged
SELECT newid() AS key23, pID AS pID23, en_EventDate AS en_EventDate23, * INTO #wflag_carcinomaNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTunchanged = 1
ALTER TABLE #wflag_carcinomaNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTkeeping ** -- 24
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTkeeping') IS NOT NULL DROP TABLE #wflag_carcinomaNOTkeeping
SELECT newid() AS key24, pID AS pID24, en_EventDate AS en_EventDate24, * INTO #wflag_carcinomaNOTkeeping FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTkeeping
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTkeeping = 1
ALTER TABLE #wflag_carcinomaNOTkeeping DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTno ** -- 25
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTno') IS NOT NULL DROP TABLE #wflag_carcinomaNOTno
SELECT newid() AS key25, pID AS pID25, en_EventDate AS en_EventDate25, * INTO #wflag_carcinomaNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTno = 1
ALTER TABLE #wflag_carcinomaNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_neoplasmNOTno ** -- 26
IF OBJECT_ID ('tempdb..#wflag_neoplasmNOTno') IS NOT NULL DROP TABLE #wflag_neoplasmNOTno
SELECT newid() AS key26, pID AS pID26, en_EventDate AS en_EventDate26, * INTO #wflag_neoplasmNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_neoplasmNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%neoplasm%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_neoplasmNOTno = 1
ALTER TABLE #wflag_neoplasmNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_progressNOTno ** -- 27
IF OBJECT_ID ('tempdb..#wflag_progressNOTno') IS NOT NULL DROP TABLE #wflag_progressNOTno
SELECT newid() AS key27, pID AS pID27, en_EventDate AS en_EventDate27, * INTO #wflag_progressNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_progressNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%progress%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_progressNOTno = 1
ALTER TABLE #wflag_progressNOTno DROp COLUMN pID, en_EventDate

-- ** wflag_deterioratNOTno ** -- 28
IF OBJECT_ID ('tempdb..#wflag_deterioratNOTno') IS NOT NULL DROP TABLE #wflag_deterioratNOTno
SELECT newid() AS key28, pID AS pID28, en_EventDate AS en_EventDate28, * INTO #wflag_deterioratNOTno FROM
( 
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_deterioratNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%deteriorat%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_deterioratNOTno = 1
ALTER TABLE #wflag_deterioratNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_relapseNOTno ** -- 29
IF OBJECT_ID ('tempdb..#wflag_relapseNOTno') IS NOT NULL DROP TABLE #wflag_relapseNOTno
SELECT newid() AS key29, pID AS pID29, en_EventDate AS en_EventDate29, * INTO #wflag_relapseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_relapseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%relapse%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_relapseNOTno = 1 
ALTER TABLE #wflag_relapseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_increaseinvolumeNOTno ** -- 30
IF OBJECT_ID ('tempdb..#wflag_increaseinvolumeNOTno') IS NOT NULL DROP TABLE #wflag_increaseinvolumeNOTno
SELECT newid() AS key30, pID AS pID30, en_EventDate AS en_EventDate30, * INTO #wflag_increaseinvolumeNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_increaseinvolumeNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%increase in volume%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_increaseinvolumeNOTno = 1
ALTER TABLE #wflag_increaseinvolumeNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_effusionNOTincreaseinsize ** -- 31
IF OBJECT_ID ('tempdb..#wflag_effusionNOTincreaseinsize') IS NOT NULL DROP TABLE #wflag_effusionNOTincreaseinsize
SELECT newid() AS key31, pID AS pID31, en_EventDate AS en_EventDate31, * INTO #wflag_effusionNOTincreaseinsize FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_effusionNOTincreaseinsize
	FROM
	(
	SELECT *,
			PATINDEX('%effusion%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_effusionNOTincreaseinsize = 1
ALTER TABLE #wflag_effusionNOTincreaseinsize DROP COLUMN pID, en_EventDate

-- ** wflag_spreadNOTno ** -- 32
IF OBJECT_ID ('tempdb..#wflag_spreadNOTno') IS NOT NULL DROP TABLE #wflag_spreadNOTno
SELECT newid() AS key32, pID AS pID32, en_EventDate AS en_EventDate32, * INTO #wflag_spreadNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_spreadNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%spread%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_spreadNOTno = 1
ALTER TABLE #wflag_spreadNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseANDsecondary ** -- 33
IF OBJECT_ID ('tempdb..#wflag_diseaseANDsecondary') IS NOT NULL DROP TABLE #wflag_diseaseANDsecondary
SELECT newid() AS key33, pID AS pID33, en_EventDate AS en_EventDate33, * INTO #wflag_diseaseANDsecondary FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseANDsecondary
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseANDsecondary = 1
ALTER TABLE #wflag_diseaseANDsecondary DROP COLUMN pID, en_EventDate

-- ** nwflag_stableNOTnot ** -- 34
IF OBJECT_ID ('tempdb..#nwflag_stableNOTnot') IS NOT NULL DROP TABLE #nwflag_stableNOTnot
SELECT newid() AS key34, pID AS pID34, en_EventDate AS en_EventDate34, * INTO #nwflag_stableNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_stableNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%stable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_stableNOTnot = 1
ALTER TABLE #nwflag_stableNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_resolvANDdisease ** -- 35
IF OBJECT_ID ('tempdb..#nwflag_resolvANDdisease') IS NOT NULL DROP TABLE #nwflag_resolvANDdisease
SELECT newid() AS key35, pID AS pID35, en_EventDate AS en_EventDate35, * INTO #nwflag_resolvANDdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_resolvANDdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_resolvANDdisease = 1
ALTER TABLE #nwflag_resolvANDdisease DROP COLUMN pID, en_EventDate

-- ** nwflag_diseaseANDno ** -- 36
IF OBJECT_ID ('tempdb..#nwflag_diseaseANDno') IS NOT NULL DROP TABLE #nwflag_diseaseANDno
SELECT newid() AS key36, pID AS pID36, en_EventDate AS en_EventDate36, * INTO #nwflag_diseaseANDno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_diseaseANDno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_diseaseANDno = 1
ALTER TABLE #nwflag_diseaseANDno DROP COLUMN pID, en_EventDate

-- ** nwflag_noevidenceNOTconclusion ** -- 37
IF OBJECT_ID ('tempdb..#nwflag_noevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_noevidenceNOTconclusion
SELECT newid() AS key37, pID AS pID37, en_EventDate AS en_EventDate37, * INTO #nwflag_noevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_noevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_noevidenceNOTconclusion = 1
ALTER TABLE #nwflag_noevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nodefiniteevidenceNOTconclusion ** -- 38
IF OBJECT_ID ('tempdb..#nwflag_nodefiniteevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_nodefiniteevidenceNOTconclusion
SELECT newid() AS key38, pID AS pID38, en_EventDate AS en_EventDate38, * INTO #nwflag_nodefiniteevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nodefiniteevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no definite evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nodefiniteevidenceNOTconclusion = 1
ALTER TABLE #nwflag_nodefiniteevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nomeasurableNOTno ** -- 39
IF OBJECT_ID ('tempdb..#nwflag_nomeasurableNOTno') IS NOT NULL DROP TABLE #nwflag_nomeasurableNOTno
SELECT newid() AS key39, pID AS pID39, en_EventDate AS en_EventDate39,  * INTO #nwflag_nomeasurableNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nomeasurableNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%no measurable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%respono measurablense%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nomeasurableNOTno = 1
ALTER TABLE #nwflag_nomeasurableNOTno DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTnot ** -- 40
IF OBJECT_ID ('tempdb..#nwflag_responseNOTnot') IS NOT NULL DROP TABLE #nwflag_responseNOTnot
SELECT newid() AS key40, pID AS pID40, en_EventDate AS en_EventDate40, * INTO #nwflag_responseNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTnot = 1
ALTER TABLE #nwflag_responseNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTno ** -- 41
IF OBJECT_ID ('tempdb..#nwflag_responseNOTno') IS NOT NULL DROP TABLE #nwflag_responseNOTno
SELECT newid() AS key41, pID AS pID41, en_EventDate AS en_EventDate41, * INTO #nwflag_responseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTno = 1 
ALTER TABLE #nwflag_responseNOTno DROP COLUMN pID, en_EventDate

-- ** mflag_responseANDmixed ** -- 42
IF OBJECT_ID ('tempdb..#mflag_responseANDmixed') IS NOT NULL DROP TABLE #mflag_responseANDmixed
SELECT newid() AS key42, pID AS pID42, en_EventDate AS en_EventDate42, * INTO #mflag_responseANDmixed FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS mflag_responseANDmixed
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE mflag_responseANDmixed = 1
ALTER TABLE #mflag_responseANDmixed DROP COLUMN pID, en_EventDate
end --

-- ** Bring it all together into #simpleNLP_Ov. **
IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'cpr' AND TABLE_NAME = 'simpleNLP_Ov')) 
BEGIN DROP TABLE simpleNLP_Ov END
SELECT unionKey AS pID, unionpID, unionts AS ts,
		wflag_metastNOTno,
		wflag_metastNOTrather,
		wflag_metastNOTstable,
		wflag_metastNOTknown,
		wflag_metastNOTdecrease,
		wflag_recurNOTno,
		wflag_malignanNOTunchanged,
		wflag_malignanNOTno,
		wflag_unchangedNOTmalignan,
		wflag_bulkNOTreduc,
		wflag_bulkNOTdecrease,
		wflag_massNOTreduc,
		wflag_massNOTdecrease,
		wflag_diseaseNOTunchanged,
		wflag_diseaseNOTstable,
		wflag_resolvNOTdisease,
		wflag_stableNOTdisease,
		wflag_responseNOTdisease,
		wflag_diseaseNOTreduc,
		wflag_diseaseNOTpaget,
		wflag_diseaseNOTdecrease,
		wflag_diseaseNOTno,
		wflag_carcinomaNOTunchanged,
		wflag_carcinomaNOTkeeping,
		wflag_carcinomaNOTno,
		wflag_neoplasmNOTno,
		wflag_progressNOTno,
		wflag_deterioratNOTno,
		wflag_relapseNOTno,
		wflag_increaseinvolumeNOTno,
		wflag_effusionNOTincreaseinsize,
		wflag_spreadNOTno,
		wflag_diseaseANDsecondary,
		nwflag_stableNOTnot,
		nwflag_resolvANDdisease,
		nwflag_diseaseANDno,
		nwflag_noevidenceNOTconclusion,
		nwflag_nodefiniteevidenceNOTconclusion,
		nwflag_nomeasurableNOTno,
		nwflag_responseNOTnot,
		nwflag_responseNOTno,
		mflag_responseANDmixed AS mixedChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 0 IN (wflag_metastNOTno, wflag_metastNOTrather, wflag_metastNOTstable, wflag_metastNOTknown, wflag_metastNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_1,
				(CASE
					WHEN wflag_recurNOTno = 0 THEN
						0
					ELSE 1
				END) +--AS worsenChk_2,
				(CASE
					WHEN 0 IN (wflag_malignanNOTunchanged, wflag_malignanNOTno, wflag_unchangedNOTmalignan) THEN
						0
					ELSE 1
				END) +--AS worsenChk_3,
				(CASE
					WHEN 0 IN (wflag_bulkNOTreduc, wflag_bulkNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_4,
				(CASE
					WHEN 0 IN (wflag_massNOTreduc, wflag_massNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_5,
				(CASE
					WHEN 0 IN (wflag_diseaseNOTunchanged, wflag_diseaseNOTstable, wflag_resolvNOTdisease, wflag_stableNOTdisease, wflag_responseNOTdisease,
								wflag_diseaseNOTreduc, wflag_diseaseNOTpaget, wflag_diseaseNOTdecrease, wflag_diseaseNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_6,
				(CASE
					WHEN 0 IN (wflag_carcinomaNOTunchanged, wflag_carcinomaNOTkeeping, wflag_carcinomaNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_7,
				(CASE
					WHEN 1 IN (wflag_neoplasmNOTno, wflag_progressNOTno, wflag_deterioratNOTno, wflag_relapseNOTno,
								wflag_increaseinvolumeNOTno, wflag_effusionNOTincreaseinsize, wflag_spreadNOTno) THEN
						1
					ELSE 0
				END) +--AS worsenChk_8,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) +--AS worsenChk_9,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) --AS worsenChk_10
			) > 0 THEN 1
			ELSE 0
		END) AS worsenChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 1 IN (nwflag_stableNOTnot, nwflag_resolvANDdisease, nwflag_diseaseANDno, nwflag_noevidenceNOTconclusion, 
								nwflag_nodefiniteevidenceNOTconclusion, nwflag_nomeasurableNOTno) THEN
						1
					ELSE 0
				END) +--AS notWorsenChk_1
				(CASE
					WHEN 1 IN (nwflag_responseNOTnot, nwflag_responseNOTno)  THEN
						1
					ELSE 0
				END) --AS notWorsenChk_2
			) > 0 THEN 1
			ELSE 0
		END) AS notWorsenChk
INTO #simpleNLP_Ov
FROM
(
SELECT * FROM( --t42
SELECT * FROM( --t41
SELECT * FROM( --t40
SELECT * FROM( --t39
SELECT * FROM( --t38
SELECT * FROM( --t37
SELECT * FROM( --t36
SELECT * FROM( --t35
SELECT * FROM( --t34
SELECT * FROM( --t33
SELECT * FROM( --t32
SELECT * FROM( --t31
SELECT * FROM( --t30
SELECT * FROM( --t29
SELECT * FROM( --t28
SELECT * FROM( --t27
SELECT * FROM( --t26
SELECT * FROM( --t25
SELECT * FROM( --t24
SELECT * FROM( --t23
SELECT * FROM( --t22
SELECT * FROM( --t21
SELECT * FROM( --t20
SELECT * FROM( --t19
SELECT * FROM( --t18
SELECT * FROM( --t17
SELECT * FROM( --t16
SELECT * FROM( --t15
SELECT * FROM( --t14
SELECT * FROM( --t13
SELECT * FROM( --t12
SELECT * FROM( --t11
SELECT * FROM( --t10
SELECT * FROM( --t9
SELECT * FROM( --t8
SELECT * FROM( --t7
SELECT * FROM( --t6
SELECT * FROM( --t5
SELECT * FROM( --t4
SELECT * FROM( --t3
SELECT * FROM( --t2
SELECT * FROM( --t1
SELECT key1 AS unionKey, pID1 AS unionpID, en_EventDate1 AS unionts FROM #wflag_metastNOTno -- 1
UNION ALL
SELECT key2 AS unionKey, pID2 AS unionpID, en_EventDate2 AS unionts FROM #wflag_metastNOTrather -- 2
UNION ALL
SELECT key3 AS unionKey, pID3 AS unionpID, en_EventDate3 AS unionts FROM #wflag_metastNOTstable-- 3
UNION ALL
SELECT key4 AS unionKey, pID4 AS unionpID, en_EventDate4 AS unionts FROM #wflag_metastNOTknown -- 4
UNION ALL
SELECT key5 AS unionKey, pID5 AS unionpID, en_EventDate5 AS unionts FROM #wflag_metastNOTdecrease -- 5
UNION ALL
SELECT key6 AS unionKey, pID6 AS unionpID, en_EventDate6 AS unionts FROM #wflag_recurNOTno -- 6
UNION ALL
SELECT key7 AS unionKey, pID7 AS unionpID, en_EventDate7 AS unionts FROM #wflag_malignanNOTunchanged -- 7
UNION ALL
SELECT key8 AS unionKey, pID8 AS unionpID, en_EventDate8 AS unionts FROM #wflag_malignanNOTno -- 8
UNION ALL
SELECT key9 AS unionKey, pID9 AS unionpID, en_EventDate9 AS unionts FROM #wflag_unchangedNOTmalignan -- 9
UNION ALL
SELECT key10 AS unionKey, pID10 AS unionpID, en_EventDate10 AS unionts FROM #wflag_bulkNOTreduc -- 10
UNION ALL
SELECT key11 AS unionKey, pID11 AS unionpID, en_EventDate11 AS unionts FROM #wflag_bulkNOTdecrease -- 11
UNION ALL
SELECT key12 AS unionKey, pID12 AS unionpID, en_EventDate12 AS unionts FROM #wflag_massNOTreduc -- 12
UNION ALL
SELECT key13 AS unionKey, pID13 AS unionpID, en_EventDate13 AS unionts FROM #wflag_massNOTdecrease -- 13
UNION ALL
SELECT key14 AS unionKey, pID14 AS unionpID, en_EventDate14 AS unionts FROM #wflag_diseaseNOTunchanged -- 14
UNION ALL
SELECT key15 AS unionKey, pID15 AS unionpID, en_EventDate15 AS unionts FROM #wflag_diseaseNOTstable -- 15
UNION ALL
SELECT key16 AS unionKey, pID16 AS unionpID, en_EventDate16 AS unionts FROM #wflag_resolvNOTdisease -- 16
UNION ALL
SELECT key17 AS unionKey, pID17 AS unionpID, en_EventDate17 AS unionts FROM #wflag_stableNOTdisease -- 17
UNION ALL
SELECT key18 AS unionKey, pID18 AS unionpID, en_EventDate18 AS unionts FROM #wflag_responseNOTdisease -- 18
UNION ALL
SELECT key19 AS unionKey, pID19 AS unionpID, en_EventDate19 AS unionts FROM #wflag_diseaseNOTreduc -- 19
UNION ALL
SELECT key20 AS unionKey, pID20 AS unionpID, en_EventDate20 AS unionts FROM #wflag_diseaseNOTpaget -- 20
UNION ALL
SELECT key21 AS unionKey, pID21 AS unionpID, en_EventDate21 AS unionts FROM #wflag_diseaseNOTdecrease -- 21
UNION ALL
SELECT key22 AS unionKey, pID22 AS unionpID, en_EventDate22 AS unionts FROM #wflag_diseaseNOTno -- 22
UNION ALL
SELECT key23 AS unionKey, pID23 AS unionpID, en_EventDate23 AS unionts FROM #wflag_carcinomaNOTunchanged -- 23
UNION ALL
SELECT key24 AS unionKey, pID24 AS unionpID, en_EventDate24 AS unionts FROM #wflag_carcinomaNOTkeeping -- 24
UNION ALL
SELECT key25 AS unionKey, pID25 AS unionpID, en_EventDate25 AS unionts FROM #wflag_carcinomaNOTno -- 25
UNION ALL
SELECT key26 AS unionKey, pID26 AS unionpID, en_EventDate26 AS unionts FROM #wflag_neoplasmNOTno -- 26
UNION ALL
SELECT key27 AS unionKey, pID27 AS unionpID, en_EventDate27 AS unionts FROM #wflag_progressNOTno -- 27
UNION ALL
SELECT key28 AS unionKey, pID28 AS unionpID, en_EventDate28 AS unionts FROM #wflag_deterioratNOTno -- 28
UNION ALL
SELECT key29 AS unionKey, pID29 AS unionpID, en_EventDate29 AS unionts FROM #wflag_relapseNOTno -- 29
UNION ALL
SELECT key30 AS unionKey, pID30 AS unionpID, en_EventDate30 AS unionts FROM #wflag_increaseinvolumeNOTno -- 30
UNION ALL
SELECT key31 AS unionKey, pID31 AS unionpID, en_EventDate31 AS unionts FROM #wflag_effusionNOTincreaseinsize -- 31
UNION ALL
SELECT key32 AS unionKey, pID32 AS unionpID, en_EventDate32 AS unionts FROM #wflag_spreadNOTno -- 32
UNION ALL
SELECT key33 AS unionKey, pID33 AS unionpID, en_EventDate33 AS unionts FROM #wflag_diseaseANDsecondary -- 33
UNION ALL
SELECT key34 AS unionKey, pID34 AS unionpID, en_EventDate34 AS unionts FROM #nwflag_stableNOTnot -- 34
UNION ALL
SELECT key35 AS unionKey, pID35 AS unionpID, en_EventDate35 AS unionts FROM #nwflag_resolvANDdisease -- 35
UNION ALL
SELECT key36 AS unionKey, pID36 AS unionpID, en_EventDate36 AS unionts FROM #nwflag_diseaseANDno -- 36
UNION ALL
SELECT key37 AS unionKey, pID37 AS unionpID, en_EventDate37 AS unionts FROM #nwflag_noevidenceNOTconclusion -- 37
UNION ALL
SELECT key38 AS unionKey, pID38 AS unionpID, en_EventDate38 AS unionts FROM #nwflag_nodefiniteevidenceNOTconclusion -- 38
UNION ALL
SELECT key39 AS unionKey, pID39 AS unionpID, en_EventDate39 AS unionts FROM #nwflag_nomeasurableNOTno -- 39
UNION ALL
SELECT key40 AS unionKey, pID40 AS unionpID, en_EventDate40 AS unionts FROM #nwflag_responseNOTnot -- 40
UNION ALL
SELECT key41 AS unionKey, pID41 AS unionpID, en_EventDate41 AS unionts FROM #nwflag_responseNOTno -- 41
UNION ALL
SELECT key42 AS unionKey, pID42 AS unionpID, en_EventDate42 AS unionts FROM #mflag_responseANDmixed -- 42
) t1
LEFT OUTER JOIN
(SELECT key1, wflag_metastNOTno FROM #wflag_metastNOTno) t
ON unionKey = t.key1
) t2
LEFT OUTER JOIN
(SELECT key2, wflag_metastNOTrather FROM #wflag_metastNOTrather) t
ON unionKey = t.key2
) t3
LEFT OUTER JOIN
(SELECT key3, wflag_metastNOTstable FROM #wflag_metastNOTstable) t
ON unionKey = t.key3
) t4
LEFT OUTER JOIN
(SELECT key4, wflag_metastNOTknown FROM #wflag_metastNOTknown) t
ON unionKey = t.key4
) t5
LEFT OUTER JOIN
(SELECT key5, wflag_metastNOTdecrease FROM #wflag_metastNOTdecrease) t
ON unionKey = t.key5
) t6
LEFT OUTER JOIN
(SELECT key6, wflag_recurNOTno FROM #wflag_recurNOTno) t
ON unionKey = t.key6
) t7
LEFT OUTER JOIN
(SELECT key7, wflag_malignanNOTunchanged FROM #wflag_malignanNOTunchanged) t
ON unionKey = t.key7
) t8
LEFT OUTER JOIN
(SELECT key8, wflag_malignanNOTno FROM #wflag_malignanNOTno) t
ON unionKey = t.key8
) t9
LEFT OUTER JOIN
(SELECT key9, wflag_unchangedNOTmalignan FROM #wflag_unchangedNOTmalignan) t
ON unionKey = t.key9
) t10
LEFT OUTER JOIN
(SELECT key10, wflag_bulkNOTreduc FROM #wflag_bulkNOTreduc) t
ON unionKey = t.key10
) t11
LEFT OUTER JOIN
(SELECT key11, wflag_bulkNOTdecrease FROM #wflag_bulkNOTdecrease) t
ON unionKey = t.key11
) t12
LEFT OUTER JOIN
(SELECT key12, wflag_massNOTreduc FROM #wflag_massNOTreduc) t
ON unionKey = t.key12
) t13
LEFT OUTER JOIN
(SELECT key13, wflag_massNOTdecrease FROM #wflag_massNOTdecrease) t
ON unionKey = t.key13
) t14
LEFT OUTER JOIN
(SELECT key14, wflag_diseaseNOTunchanged FROM #wflag_diseaseNOTunchanged) t
ON unionKey = t.key14
) t15
LEFT OUTER JOIN
(SELECT key15, wflag_diseaseNOTstable FROM #wflag_diseaseNOTstable) t
ON unionKey = t.key15
) t16
LEFT OUTER JOIN
(SELECT key16, wflag_resolvNOTdisease FROM #wflag_resolvNOTdisease) t
ON unionKey = t.key16
) t17
LEFT OUTER JOIN
(SELECT key17, wflag_stableNOTdisease FROM #wflag_stableNOTdisease) t
ON unionKey = t.key17
) t18
LEFT OUTER JOIN
(SELECT key18, wflag_responseNOTdisease FROM #wflag_responseNOTdisease) t
ON unionKey = t.key18
) t19
LEFT OUTER JOIN
(SELECT key19, wflag_diseaseNOTreduc FROM #wflag_diseaseNOTreduc) t
ON unionKey = t.key19
) t20
LEFT OUTER JOIN
(SELECT key20, wflag_diseaseNOTpaget FROM #wflag_diseaseNOTpaget) t
ON unionKey = t.key20
) t21
LEFT OUTER JOIN
(SELECT key21, wflag_diseaseNOTdecrease FROM #wflag_diseaseNOTdecrease) t
ON unionKey = t.key21
) t22
LEFT OUTER JOIN
(SELECT key22, wflag_diseaseNOTno FROM #wflag_diseaseNOTno) t
ON unionKey = t.key22
) t23
LEFT OUTER JOIN
(SELECT key23, wflag_carcinomaNOTunchanged FROM #wflag_carcinomaNOTunchanged) t
ON unionKey = t.key23
) t24
LEFT OUTER JOIN
(SELECT key24, wflag_carcinomaNOTkeeping FROM #wflag_carcinomaNOTkeeping) t
ON unionKey = t.key24
) t25
LEFT OUTER JOIN
(SELECT key25, wflag_carcinomaNOTno FROM #wflag_carcinomaNOTno) t
ON unionKey = t.key25
) t26
LEFT OUTER JOIN
(SELECT key26, wflag_neoplasmNOTno FROM #wflag_neoplasmNOTno) t
ON unionKey = t.key26
) t27
LEFT OUTER JOIN
(SELECT key27, wflag_progressNOTno FROM #wflag_progressNOTno) t
ON unionKey = t.key27
) t28
LEFT OUTER JOIN
(SELECT key28, wflag_deterioratNOTno FROM #wflag_deterioratNOTno) t
ON unionKey = t.key28
) t29
LEFT OUTER JOIN
(SELECT key29, wflag_relapseNOTno FROM #wflag_relapseNOTno) t
ON unionKey = t.key29
) t30
LEFT OUTER JOIN
(SELECT key30, wflag_increaseinvolumeNOTno FROM #wflag_increaseinvolumeNOTno) t
ON unionKey = t.key30
) t31
LEFT OUTER JOIN
(SELECT key31, wflag_effusionNOTincreaseinsize FROM #wflag_effusionNOTincreaseinsize) t
ON unionKey = t.key31
) t32
LEFT OUTER JOIN
(SELECT key32, wflag_spreadNOTno FROM #wflag_spreadNOTno) t
ON unionKey = t.key32
) t33
LEFT OUTER JOIN
(SELECT key33, wflag_diseaseANDsecondary FROM #wflag_diseaseANDsecondary) t
ON unionKey = t.key33
) t34
LEFT OUTER JOIN
(SELECT key34, nwflag_stableNOTnot FROM #nwflag_stableNOTnot) t
ON unionKey = t.key34
) t35
LEFT OUTER JOIN
(SELECT key35, nwflag_resolvANDdisease FROM #nwflag_resolvANDdisease) t
ON unionKey = t.key35
) t36
LEFT OUTER JOIN
(SELECT key36, nwflag_diseaseANDno FROM #nwflag_diseaseANDno) t
ON unionKey = t.key36
) t37
LEFT OUTER JOIN
(SELECT key37, nwflag_noevidenceNOTconclusion FROM #nwflag_noevidenceNOTconclusion) t
ON unionKey = t.key37
) t38
LEFT OUTER JOIN
(SELECT key38, nwflag_nodefiniteevidenceNOTconclusion FROM #nwflag_nodefiniteevidenceNOTconclusion) t
ON unionKey = t.key38
) t39
LEFT OUTER JOIN
(SELECT key39, nwflag_nomeasurableNOTno FROM #nwflag_nomeasurableNOTno) t
ON unionKey = t.key39
) t40
LEFT OUTER JOIN
(SELECT key40, nwflag_responseNOTnot FROM #nwflag_responseNOTnot) t
ON unionKey = t.key40
) t41
LEFT OUTER JOIN
(SELECT key41, nwflag_responseNOTno FROM #nwflag_responseNOTno) t
ON unionKey = t.key41
) t42
LEFT OUTER JOIN
(SELECT key42, mflag_responseANDmixed FROM #mflag_responseANDmixed) t
ON unionKey = t.key42
) t43
-- ** Change NULL to zero. **
begin --
UPDATE #simpleNLP_Ov SET wflag_metastNOTno = 0 WHERE wflag_metastNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_metastNOTrather = 0 WHERE wflag_metastNOTrather IS NULL
UPDATE #simpleNLP_Ov SET wflag_metastNOTstable = 0 WHERE wflag_metastNOTstable IS NULL
UPDATE #simpleNLP_Ov SET wflag_metastNOTknown = 0 WHERE wflag_metastNOTknown IS NULL
UPDATE #simpleNLP_Ov SET wflag_metastNOTdecrease = 0 WHERE wflag_metastNOTdecrease IS NULL
UPDATE #simpleNLP_Ov SET wflag_recurNOTno = 0 WHERE wflag_recurNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_malignanNOTunchanged = 0 WHERE wflag_malignanNOTunchanged IS NULL
UPDATE #simpleNLP_Ov SET wflag_malignanNOTno = 0 WHERE wflag_malignanNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_unchangedNOTmalignan = 0 WHERE wflag_unchangedNOTmalignan IS NULL
UPDATE #simpleNLP_Ov SET wflag_bulkNOTreduc = 0 WHERE wflag_bulkNOTreduc IS NULL
UPDATE #simpleNLP_Ov SET wflag_bulkNOTdecrease = 0 WHERE wflag_bulkNOTdecrease IS NULL
UPDATE #simpleNLP_Ov SET wflag_massNOTreduc = 0 WHERE wflag_massNOTreduc IS NULL
UPDATE #simpleNLP_Ov SET wflag_massNOTdecrease = 0 WHERE wflag_massNOTdecrease IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTunchanged = 0 WHERE wflag_diseaseNOTunchanged IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTstable = 0 WHERE wflag_diseaseNOTstable IS NULL
UPDATE #simpleNLP_Ov SET wflag_resolvNOTdisease = 0 WHERE wflag_resolvNOTdisease IS NULL
UPDATE #simpleNLP_Ov SET wflag_stableNOTdisease = 0 WHERE wflag_stableNOTdisease IS NULL
UPDATE #simpleNLP_Ov SET wflag_responseNOTdisease = 0 WHERE wflag_responseNOTdisease IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTreduc = 0 WHERE wflag_diseaseNOTreduc IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTpaget = 0 WHERE wflag_diseaseNOTpaget IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTdecrease = 0 WHERE wflag_diseaseNOTdecrease IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseNOTno = 0 WHERE wflag_diseaseNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_carcinomaNOTunchanged = 0 WHERE wflag_carcinomaNOTunchanged IS NULL
UPDATE #simpleNLP_Ov SET wflag_carcinomaNOTkeeping = 0 WHERE wflag_carcinomaNOTkeeping IS NULL
UPDATE #simpleNLP_Ov SET wflag_carcinomaNOTno = 0 WHERE wflag_carcinomaNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_neoplasmNOTno = 0 WHERE wflag_neoplasmNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_progressNOTno = 0 WHERE wflag_progressNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_deterioratNOTno = 0 WHERE wflag_deterioratNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_relapseNOTno = 0 WHERE wflag_relapseNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_increaseinvolumeNOTno = 0 WHERE wflag_increaseinvolumeNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_effusionNOTincreaseinsize = 0 WHERE wflag_effusionNOTincreaseinsize IS NULL
UPDATE #simpleNLP_Ov SET wflag_spreadNOTno = 0 WHERE wflag_spreadNOTno IS NULL
UPDATE #simpleNLP_Ov SET wflag_diseaseANDsecondary = 0 WHERE wflag_diseaseANDsecondary IS NULL
UPDATE #simpleNLP_Ov SET nwflag_stableNOTnot = 0 WHERE nwflag_stableNOTnot IS NULL
UPDATE #simpleNLP_Ov SET nwflag_resolvANDdisease = 0 WHERE nwflag_resolvANDdisease IS NULL
UPDATE #simpleNLP_Ov SET nwflag_diseaseANDno = 0 WHERE nwflag_diseaseANDno IS NULL
UPDATE #simpleNLP_Ov SET nwflag_noevidenceNOTconclusion = 0 WHERE nwflag_noevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_Ov SET nwflag_nodefiniteevidenceNOTconclusion = 0 WHERE nwflag_nodefiniteevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_Ov SET nwflag_nomeasurableNOTno = 0 WHERE nwflag_nomeasurableNOTno IS NULL
UPDATE #simpleNLP_Ov SET nwflag_responseNOTnot = 0 WHERE nwflag_responseNOTnot IS NULL
UPDATE #simpleNLP_Ov SET nwflag_responseNOTno = 0 WHERE nwflag_responseNOTno IS NULL
UPDATE #simpleNLP_Ov SET mixedChk = 0 WHERE mixedChk IS NULL
end --


-- **************************************
-- ***** Colorectal cohort patients *****
-- **************************************

-- ** Prepare some prerequisites. **
begin --

DECLARE @WLcolorectal table (id varchar(8))
INSERT INTO @WLcolorectal VALUES ('11003201'),('11003228'),('11003283')
IF OBJECT_ID ('tempdb..#ColorectalPatients') IS NOT NULL DROP TABLE #ColorectalPatients;
CREATE TABLE #ColorectalPatients(pID int);
INSERT INTO #ColorectalPatients(pID)
SELECT DISTINCT wc_PatientID ColorectalWatchlistPID
FROM PPMQuery.leeds.Watch
WHERE wc_WatchDefinitionID IN (SELECT id FROM @WLcolorectal)
ORDER BY ColorectalWatchlistPID;


IF OBJECT_ID ('tempdb..#recurrences_CR') IS NOT NULL DROP TABLE #recurrences_CR
CREATE TABLE #recurrences_CR(
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
INSERT INTO #recurrences_CR(
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
		WHERE dx_PatientID IN (SELECT * FROM #ColorectalPatients))
		AND Cohort = 'Colorectal'
ORDER BY recurpID
-- This table is initially constructed without an uniqueidentifier
-- because of issues with duplicates in the ACNRes table. I add
-- it now.
ALTER TABLE #recurrences_CR ADD recurIDkey uniqueidentifier
UPDATE #recurrences_CR SET recurIDkey = newid()
-- SELECT * FROM #recurrences_CR ORDER BY recurpID


-- ** worsening **
-- ** This table collates all progression and recurrences (hereadter 
-- ** called "worsening") into one column.
IF OBJECT_ID ('tempdb..#oneColWorsening_CR') IS NOT NULL DROP TABLE #oneColWorsening_CR
SELECT * INTO #oneColWorsening_CR
FROM(
	SELECT newid() worsenIDkey, recurpID worsenpID, prevWorsenCnt, worseningDate, DOB, CAST(FLOOR(DATEDIFF(DAY, DOB, worseningDate)/(365.4*5)) AS real) AS ageBandAtWorseningDate
	FROM #recurrences_CR
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
UPDATE #oneColWorsening_CR 
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
UPDATE #oneColWorsening_CR SET ageBandAtWorseningDate = 17 WHERE ageBandAtWorseningDate > 17
-- SELECT * FROM #oneColWorsening_CR ORDER BY worsenpID, worseningDate
end --

-- ** Prepare the portion of text to be reviewed. **
IF OBJECT_ID ('tempdb..#extractedText') IS NOT NULL DROP TABLE #extractedText
SELECT DISTINCT pID, en_EventDate, leftWasCut
INTO #extractedText
FROM
(
SELECT en_EventID, en_EventDate, en_PatientID, REPLACE(SUBSTRING(en_TextResult, CHARINDEX('CONCLUSION:', en_TextResult), LEN(en_TextResult)), 'CONCLUSION:', 'myCONCLUSION') AS leftWasCut
FROM PPMQuery.leeds.Investigations
WHERE en_TextResult LIKE '%CONCLUSION:%'
AND en_PatientID IN (SELECT * FROM #ColorectalPatients) ) t1
JOIN
(SELECT DISTINCT ex_CodedIdentifier pID, ex_PatientID
FROM ACNRes.dbo.sdt_RP_BR_CR_OV_COMBINED_FLAT_TABLE_2013_FINAL
WHERE ex_PatientID IN (
	SELECT DISTINCT dx_PatientID pID
	FROM PPMQuery.leeds.Diagnosis
	WHERE dx_PatientID IN (SELECT * FROM #ColorectalPatients))) t2
ON t1.en_PatientID = t2.ex_PatientID
JOIN
(SELECT * FROM #recurrences_CR ) t3
ON t2.pID = t3.recurpID
WHERE en_EventDate < '2012-04-13'
ORDER BY pID, en_EventDate

-- ** Compute the indicators of interest. **
-- **********************************
-- ** I'm sure there is a clean way to do the following by creating a list of 
-- ** keywords and their negations, and then evaluating a concatonated character 
-- ** command but I think I will be quicker just hard coding everything.
-- **********************************
begin --
-- ** wflag_metastNOTno ** -- 1
IF OBJECT_ID ('tempdb..#wflag_metastNOTno') IS NOT NULL DROP TABLE #wflag_metastNOTno
SELECT newid() AS key1, pID AS pID1, en_EventDate AS en_EventDate1, * INTO #wflag_metastNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTno = 1
ALTER TABLE #wflag_metastNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTrather ** -- 2
IF OBJECT_ID ('tempdb..#wflag_metastNOTrather') IS NOT NULL DROP TABLE #wflag_metastNOTrather
SELECT newid() AS key2, pID AS pID2, en_EventDate AS en_EventDate2, * INTO #wflag_metastNOTrather FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTrather
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% rather %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTrather = 1
ALTER TABLE #wflag_metastNOTrather DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTstable ** -- 3
IF OBJECT_ID ('tempdb..#wflag_metastNOTstable') IS NOT NULL DROP TABLE #wflag_metastNOTstable
SELECT newid() AS key3, pID AS pID3, en_EventDate AS en_EventDate3, * INTO #wflag_metastNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('% stable %', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTstable = 1
ALTER TABLE #wflag_metastNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTknown ** -- 4
IF OBJECT_ID ('tempdb..#wflag_metastNOTknown') IS NOT NULL DROP TABLE #wflag_metastNOTknown
SELECT newid() AS key4, pID AS pID4, en_EventDate AS en_EventDate4, * INTO #wflag_metastNOTknown FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTknown
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%known%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTknown = 1
ALTER TABLE #wflag_metastNOTknown DROP COLUMN pID, en_EventDate

-- ** wflag_metastNOTdecrease ** -- 5
IF OBJECT_ID ('tempdb..#wflag_metastNOTdecrease') IS NOT NULL DROP TABLE #wflag_metastNOTdecrease
SELECT newid() AS key5, pID AS pID5, en_EventDate AS en_EventDate5, * INTO #wflag_metastNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_metastNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%metast%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%metast%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_metastNOTdecrease = 1
ALTER TABLE #wflag_metastNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_recurNOTno ** -- 6
IF OBJECT_ID ('tempdb..#wflag_recurNOTno') IS NOT NULL DROP TABLE #wflag_recurNOTno
SELECT newid() AS key6, pID AS pID6, en_EventDate AS en_EventDate6, * INTO #wflag_recurNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_recurNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%recur%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%recur%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_recurNOTno = 1
ALTER TABLE #wflag_recurNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTunchanged ** -- 7
IF OBJECT_ID ('tempdb..#wflag_malignanNOTunchanged') IS NOT NULL DROP TABLE #wflag_malignanNOTunchanged
SELECT newid() AS key7, pID AS pID7, en_EventDate AS en_EventDate7, * INTO #wflag_malignanNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTunchanged = 1
ALTER TABLE #wflag_malignanNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_malignanNOTno ** -- 8
IF OBJECT_ID ('tempdb..#wflag_malignanNOTno') IS NOT NULL DROP TABLE #wflag_malignanNOTno
SELECT newid() AS key8, pID AS pID8, en_EventDate AS en_EventDate8, * INTO #wflag_malignanNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_malignanNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%malignan%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_malignanNOTno = 1
ALTER TABLE #wflag_malignanNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_unchangedNOTmalignan ** -- 9
IF OBJECT_ID ('tempdb..#wflag_unchangedNOTmalignan') IS NOT NULL DROP TABLE #wflag_unchangedNOTmalignan
SELECT newid() AS key9, pID AS pID9, en_EventDate AS en_EventDate9, * INTO #wflag_unchangedNOTmalignan FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_unchangedNOTmalignan
	FROM
	(
	SELECT *,
			PATINDEX('%malignan%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut)), PATINDEX('%unchanged%', SUBSTRING(leftWasCut, PATINDEX('%malignan%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_unchangedNOTmalignan = 1
ALTER TABLE #wflag_unchangedNOTmalignan DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTreduc ** -- 10
IF OBJECT_ID ('tempdb..#wflag_bulkNOTreduc') IS NOT NULL DROP TABLE #wflag_bulkNOTreduc
SELECT newid() AS key10, pID AS pID10, en_EventDate AS en_EventDate10, * INTO #wflag_bulkNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTreduc = 1
ALTER TABLE #wflag_bulkNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_bulkNOTdecrease ** -- 11
IF OBJECT_ID ('tempdb..#wflag_bulkNOTdecrease') IS NOT NULL DROP TABLE #wflag_bulkNOTdecrease
SELECT newid() AS key11, pID AS pID11, en_EventDate AS en_EventDate11, * INTO #wflag_bulkNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_bulkNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%bulk%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%bulk%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_bulkNOTdecrease = 1
ALTER TABLE #wflag_bulkNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTreduc ** -- 12
IF OBJECT_ID ('tempdb..#wflag_massNOTreduc') IS NOT NULL DROP TABLE #wflag_massNOTreduc
SELECT newid() AS key12, pID AS pID12, en_EventDate AS en_EventDate12, * INTO #wflag_massNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTreduc = 1
ALTER TABLE #wflag_massNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_massNOTdecrease ** -- 13
IF OBJECT_ID ('tempdb..#wflag_massNOTdecrease') IS NOT NULL DROP TABLE #wflag_massNOTdecrease
SELECT newid() AS key13, pID AS pID13, en_EventDate AS en_EventDate13, * INTO  #wflag_massNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_massNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%mass%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%mass%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_massNOTdecrease = 1
ALTER TABLE #wflag_massNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTunchanged ** -- 14
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTunchanged') IS NOT NULL DROP TABLE #wflag_diseaseNOTunchanged
SELECT newid() AS key14, pID AS pID14, en_EventDate AS en_EventDate14, * INTO #wflag_diseaseNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTunchanged = 1
ALTER TABLE #wflag_diseaseNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTstable ** -- 15
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTstable') IS NOT NULL DROP TABLE #wflag_diseaseNOTstable
SELECT newid() AS key15, pID AS pID15, en_EventDate AS en_EventDate15, * INTO #wflag_diseaseNOTstable FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTstable
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%stable%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTstable = 1
ALTER TABLE #wflag_diseaseNOTstable DROP COLUMN pID, en_EventDate

-- ** wflag_resolvNOTdisease ** -- 16
IF OBJECT_ID ('tempdb..#wflag_resolvNOTdisease') IS NOT NULL DROP TABLE #wflag_resolvNOTdisease
SELECT newid() AS key16, pID AS pID16, en_EventDate AS en_EventDate16, * INTO #wflag_resolvNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_resolvNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_resolvNOTdisease = 1
ALTER TABLE #wflag_resolvNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_stableNOTdisease ** -- 17
IF OBJECT_ID ('tempdb..#wflag_stableNOTdisease') IS NOT NULL DROP TABLE #wflag_stableNOTdisease
SELECT newid() AS key17, pID AS pID17, en_EventDate AS en_EventDate17, * INTO #wflag_stableNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_stableNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%stable%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_stableNOTdisease = 1
ALTER TABLE #wflag_stableNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_responseNOTdisease ** -- 18
IF OBJECT_ID ('tempdb..#wflag_responseNOTdisease') IS NOT NULL DROP TABLE #wflag_responseNOTdisease
SELECT newid() AS key18, pID AS pID18, en_EventDate AS en_EventDate18, * INTO #wflag_responseNOTdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_responseNOTdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%response%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_responseNOTdisease = 1
ALTER TABLE #wflag_responseNOTdisease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTreduc ** -- 19
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTreduc') IS NOT NULL DROP TABLE #wflag_diseaseNOTreduc
SELECT newid() AS key19, pID as pID19, en_EventDate AS en_EventDate19, * INTO #wflag_diseaseNOTreduc FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTreduc
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%reduc%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTreduc = 1
ALTER TABLE #wflag_diseaseNOTreduc DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTpaget ** -- 20
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTpaget') IS NOT NULL DROP TABLE #wflag_diseaseNOTpaget
SELECT newid() AS key20, pID AS pID20, en_EventDate AS en_EventDate20, * INTO #wflag_diseaseNOTpaget FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTpaget
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%paget%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTpaget = 1
ALTER TABLE #wflag_diseaseNOTpaget DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTdecrease ** -- 21
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTdecrease') IS NOT NULL DROP TABLE #wflag_diseaseNOTdecrease
SELECT newid() AS key21, pID as pID21, en_EventDate AS en_EventDate21, * INTO #wflag_diseaseNOTdecrease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTdecrease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%decrease%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTdecrease = 1
ALTER TABLE #wflag_diseaseNOTdecrease DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseNOTno ** -- 22
IF OBJECT_ID ('tempdb..#wflag_diseaseNOTno') IS NOT NULL DROP TABLE #wflag_diseaseNOTno
SELECT newid() AS key22, pID as pID22, en_EventDate AS en_EventDate22, * INTO #wflag_diseaseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseNOTno = 1
ALTER TABLE #wflag_diseaseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTunchanged ** -- 23
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTunchanged') IS NOT NULL DROP TABLE #wflag_carcinomaNOTunchanged
SELECT newid() AS key23, pID AS pID23, en_EventDate AS en_EventDate23, * INTO #wflag_carcinomaNOTunchanged FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTunchanged
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%unchanged%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTunchanged = 1
ALTER TABLE #wflag_carcinomaNOTunchanged DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTkeeping ** -- 24
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTkeeping') IS NOT NULL DROP TABLE #wflag_carcinomaNOTkeeping
SELECT newid() AS key24, pID AS pID24, en_EventDate AS en_EventDate24, * INTO #wflag_carcinomaNOTkeeping FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTkeeping
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('%keeping%', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTkeeping = 1
ALTER TABLE #wflag_carcinomaNOTkeeping DROP COLUMN pID, en_EventDate

-- ** wflag_carcinomaNOTno ** -- 25
IF OBJECT_ID ('tempdb..#wflag_carcinomaNOTno') IS NOT NULL DROP TABLE #wflag_carcinomaNOTno
SELECT newid() AS key25, pID AS pID25, en_EventDate AS en_EventDate25, * INTO #wflag_carcinomaNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_carcinomaNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%carcinoma%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%carcinoma%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_carcinomaNOTno = 1
ALTER TABLE #wflag_carcinomaNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_neoplasmNOTno ** -- 26
IF OBJECT_ID ('tempdb..#wflag_neoplasmNOTno') IS NOT NULL DROP TABLE #wflag_neoplasmNOTno
SELECT newid() AS key26, pID AS pID26, en_EventDate AS en_EventDate26, * INTO #wflag_neoplasmNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_neoplasmNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%neoplasm%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%neoplasm%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_neoplasmNOTno = 1
ALTER TABLE #wflag_neoplasmNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_progressNOTno ** -- 27
IF OBJECT_ID ('tempdb..#wflag_progressNOTno') IS NOT NULL DROP TABLE #wflag_progressNOTno
SELECT newid() AS key27, pID AS pID27, en_EventDate AS en_EventDate27, * INTO #wflag_progressNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_progressNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%progress%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%progress%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_progressNOTno = 1
ALTER TABLE #wflag_progressNOTno DROp COLUMN pID, en_EventDate

-- ** wflag_deterioratNOTno ** -- 28
IF OBJECT_ID ('tempdb..#wflag_deterioratNOTno') IS NOT NULL DROP TABLE #wflag_deterioratNOTno
SELECT newid() AS key28, pID AS pID28, en_EventDate AS en_EventDate28, * INTO #wflag_deterioratNOTno FROM
( 
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_deterioratNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%deteriorat%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%deteriorat%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_deterioratNOTno = 1
ALTER TABLE #wflag_deterioratNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_relapseNOTno ** -- 29
IF OBJECT_ID ('tempdb..#wflag_relapseNOTno') IS NOT NULL DROP TABLE #wflag_relapseNOTno
SELECT newid() AS key29, pID AS pID29, en_EventDate AS en_EventDate29, * INTO #wflag_relapseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_relapseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%relapse%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%relapse%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_relapseNOTno = 1 
ALTER TABLE #wflag_relapseNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_increaseinvolumeNOTno ** -- 30
IF OBJECT_ID ('tempdb..#wflag_increaseinvolumeNOTno') IS NOT NULL DROP TABLE #wflag_increaseinvolumeNOTno
SELECT newid() AS key30, pID AS pID30, en_EventDate AS en_EventDate30, * INTO #wflag_increaseinvolumeNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_increaseinvolumeNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%increase in volume%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%increase in volume%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_increaseinvolumeNOTno = 1
ALTER TABLE #wflag_increaseinvolumeNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_effusionNOTincreaseinsize ** -- 31
IF OBJECT_ID ('tempdb..#wflag_effusionNOTincreaseinsize') IS NOT NULL DROP TABLE #wflag_effusionNOTincreaseinsize
SELECT newid() AS key31, pID AS pID31, en_EventDate AS en_EventDate31, * INTO #wflag_effusionNOTincreaseinsize FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_effusionNOTincreaseinsize
	FROM
	(
	SELECT *,
			PATINDEX('%effusion%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut)), PATINDEX('%increase in size%', LEFT(leftWasCut, PATINDEX('%effusion%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_effusionNOTincreaseinsize = 1
ALTER TABLE #wflag_effusionNOTincreaseinsize DROP COLUMN pID, en_EventDate

-- ** wflag_spreadNOTno ** -- 32
IF OBJECT_ID ('tempdb..#wflag_spreadNOTno') IS NOT NULL DROP TABLE #wflag_spreadNOTno
SELECT newid() AS key32, pID AS pID32, en_EventDate AS en_EventDate32, * INTO #wflag_spreadNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_spreadNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%spread%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%spread%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_spreadNOTno = 1
ALTER TABLE #wflag_spreadNOTno DROP COLUMN pID, en_EventDate

-- ** wflag_diseaseANDsecondary ** -- 33
IF OBJECT_ID ('tempdb..#wflag_diseaseANDsecondary') IS NOT NULL DROP TABLE #wflag_diseaseANDsecondary
SELECT newid() AS key33, pID AS pID33, en_EventDate AS en_EventDate33, * INTO #wflag_diseaseANDsecondary FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS wflag_diseaseANDsecondary
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('%secondary%', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE wflag_diseaseANDsecondary = 1
ALTER TABLE #wflag_diseaseANDsecondary DROP COLUMN pID, en_EventDate

-- ** nwflag_stableNOTnot ** -- 34
IF OBJECT_ID ('tempdb..#nwflag_stableNOTnot') IS NOT NULL DROP TABLE #nwflag_stableNOTnot
SELECT newid() AS key34, pID AS pID34, en_EventDate AS en_EventDate34, * INTO #nwflag_stableNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_stableNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%stable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%stable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_stableNOTnot = 1
ALTER TABLE #nwflag_stableNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_resolvANDdisease ** -- 35
IF OBJECT_ID ('tempdb..#nwflag_resolvANDdisease') IS NOT NULL DROP TABLE #nwflag_resolvANDdisease
SELECT newid() AS key35, pID AS pID35, en_EventDate AS en_EventDate35, * INTO #nwflag_resolvANDdisease FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_resolvANDdisease
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)) AS postTextChunk,
			PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))) AS patindexVal_negation,
			LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)))) AS postTextChunk2,
			CHARINDEX('.', LEFT(SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut)), PATINDEX('%resolv%', SUBSTRING(leftWasCut, PATINDEX('%disease%', leftWasCut), LEN(leftWasCut))))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_resolvANDdisease = 1
ALTER TABLE #nwflag_resolvANDdisease DROP COLUMN pID, en_EventDate

-- ** nwflag_diseaseANDno ** -- 36
IF OBJECT_ID ('tempdb..#nwflag_diseaseANDno') IS NOT NULL DROP TABLE #nwflag_diseaseANDno
SELECT newid() AS key36, pID AS pID36, en_EventDate AS en_EventDate36, * INTO #nwflag_diseaseANDno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					1
			END
			) AS nwflag_diseaseANDno
	FROM
	(
	SELECT *,
			PATINDEX('%disease%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%disease%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_diseaseANDno = 1
ALTER TABLE #nwflag_diseaseANDno DROP COLUMN pID, en_EventDate

-- ** nwflag_noevidenceNOTconclusion ** -- 37
IF OBJECT_ID ('tempdb..#nwflag_noevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_noevidenceNOTconclusion
SELECT newid() AS key37, pID AS pID37, en_EventDate AS en_EventDate37, * INTO #nwflag_noevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_noevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_noevidenceNOTconclusion = 1
ALTER TABLE #nwflag_noevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nodefiniteevidenceNOTconclusion ** -- 38
IF OBJECT_ID ('tempdb..#nwflag_nodefiniteevidenceNOTconclusion') IS NOT NULL DROP TABLE #nwflag_nodefiniteevidenceNOTconclusion
SELECT newid() AS key38, pID AS pID38, en_EventDate AS en_EventDate38, * INTO #nwflag_nodefiniteevidenceNOTconclusion FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nodefiniteevidenceNOTconclusion
	FROM
	(
	SELECT *,
			PATINDEX('%no definite evidence%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut)), PATINDEX('%conclusion%', LEFT(leftWasCut, PATINDEX('%no definite evidence%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nodefiniteevidenceNOTconclusion = 1
ALTER TABLE #nwflag_nodefiniteevidenceNOTconclusion DROP COLUMN pID, en_EventDate

-- ** nwflag_nomeasurableNOTno ** -- 39
IF OBJECT_ID ('tempdb..#nwflag_nomeasurableNOTno') IS NOT NULL DROP TABLE #nwflag_nomeasurableNOTno
SELECT newid() AS key39, pID AS pID39, en_EventDate AS en_EventDate39,  * INTO #nwflag_nomeasurableNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_nomeasurableNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%no measurable%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%respono measurablense%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%no measurable%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_nomeasurableNOTno = 1
ALTER TABLE #nwflag_nomeasurableNOTno DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTnot ** -- 40
IF OBJECT_ID ('tempdb..#nwflag_responseNOTnot') IS NOT NULL DROP TABLE #nwflag_responseNOTnot
SELECT newid() AS key40, pID AS pID40, en_EventDate AS en_EventDate40, * INTO #nwflag_responseNOTnot FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTnot
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% not %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTnot = 1
ALTER TABLE #nwflag_responseNOTnot DROP COLUMN pID, en_EventDate

-- ** nwflag_responseNOTno ** -- 41
IF OBJECT_ID ('tempdb..#nwflag_responseNOTno') IS NOT NULL DROP TABLE #nwflag_responseNOTno
SELECT newid() AS key41, pID AS pID41, en_EventDate AS en_EventDate41, * INTO #nwflag_responseNOTno FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					1
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS nwflag_responseNOTno
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('% no %', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE nwflag_responseNOTno = 1 
ALTER TABLE #nwflag_responseNOTno DROP COLUMN pID, en_EventDate

-- ** mflag_responseANDmixed ** -- 42
IF OBJECT_ID ('tempdb..#mflag_responseANDmixed') IS NOT NULL DROP TABLE #mflag_responseANDmixed
SELECT newid() AS key42, pID AS pID42, en_EventDate AS en_EventDate42, * INTO #mflag_responseANDmixed FROM
(
	SELECT *,
			(CASE
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop > 0) THEN
					0
				WHEN (patindexVal_key > 0 AND patindexVal_negation > 0 AND chrindexVal_fullstop !> 0) THEN
					1
				WHEN (patindexVal_key > 0 AND patindexVal_negation !> 0) THEN
					0
				WHEN (patindexVal_key !> 0) THEN
					0
			END
			) AS mflag_responseANDmixed
	FROM
	(
	SELECT *,
			PATINDEX('%response%', leftWasCut) AS patindexVal_key,
			LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)) AS prevTextChunk,
			PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))) AS patindexVal_negation,
			SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut)) AS prevTextChunk2,
			CHARINDEX('.', SUBSTRING(LEFT(leftWasCut, PATINDEX('%response%', leftWasCut)), PATINDEX('%mixed%', LEFT(leftWasCut, PATINDEX('%response%', leftWasCut))), LEN(leftWasCut))) AS chrindexVal_fullstop
	FROM #extractedText
	) t1
) t1b
WHERE mflag_responseANDmixed = 1
ALTER TABLE #mflag_responseANDmixed DROP COLUMN pID, en_EventDate
end --

-- ** Bring it all together into #simpleNLP_CR. **
IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'cpr' AND TABLE_NAME = 'simpleNLP_CR')) 
BEGIN DROP TABLE simpleNLP_CR END
SELECT unionKey AS pID, unionpID, unionts AS ts,
		wflag_metastNOTno,
		wflag_metastNOTrather,
		wflag_metastNOTstable,
		wflag_metastNOTknown,
		wflag_metastNOTdecrease,
		wflag_recurNOTno,
		wflag_malignanNOTunchanged,
		wflag_malignanNOTno,
		wflag_unchangedNOTmalignan,
		wflag_bulkNOTreduc,
		wflag_bulkNOTdecrease,
		wflag_massNOTreduc,
		wflag_massNOTdecrease,
		wflag_diseaseNOTunchanged,
		wflag_diseaseNOTstable,
		wflag_resolvNOTdisease,
		wflag_stableNOTdisease,
		wflag_responseNOTdisease,
		wflag_diseaseNOTreduc,
		wflag_diseaseNOTpaget,
		wflag_diseaseNOTdecrease,
		wflag_diseaseNOTno,
		wflag_carcinomaNOTunchanged,
		wflag_carcinomaNOTkeeping,
		wflag_carcinomaNOTno,
		wflag_neoplasmNOTno,
		wflag_progressNOTno,
		wflag_deterioratNOTno,
		wflag_relapseNOTno,
		wflag_increaseinvolumeNOTno,
		wflag_effusionNOTincreaseinsize,
		wflag_spreadNOTno,
		wflag_diseaseANDsecondary,
		nwflag_stableNOTnot,
		nwflag_resolvANDdisease,
		nwflag_diseaseANDno,
		nwflag_noevidenceNOTconclusion,
		nwflag_nodefiniteevidenceNOTconclusion,
		nwflag_nomeasurableNOTno,
		nwflag_responseNOTnot,
		nwflag_responseNOTno,
		mflag_responseANDmixed AS mixedChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 0 IN (wflag_metastNOTno, wflag_metastNOTrather, wflag_metastNOTstable, wflag_metastNOTknown, wflag_metastNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_1,
				(CASE
					WHEN wflag_recurNOTno = 0 THEN
						0
					ELSE 1
				END) +--AS worsenChk_2,
				(CASE
					WHEN 0 IN (wflag_malignanNOTunchanged, wflag_malignanNOTno, wflag_unchangedNOTmalignan) THEN
						0
					ELSE 1
				END) +--AS worsenChk_3,
				(CASE
					WHEN 0 IN (wflag_bulkNOTreduc, wflag_bulkNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_4,
				(CASE
					WHEN 0 IN (wflag_massNOTreduc, wflag_massNOTdecrease) THEN
						0
					ELSE 1
				END) +--AS worsenChk_5,
				(CASE
					WHEN 0 IN (wflag_diseaseNOTunchanged, wflag_diseaseNOTstable, wflag_resolvNOTdisease, wflag_stableNOTdisease, wflag_responseNOTdisease,
								wflag_diseaseNOTreduc, wflag_diseaseNOTpaget, wflag_diseaseNOTdecrease, wflag_diseaseNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_6,
				(CASE
					WHEN 0 IN (wflag_carcinomaNOTunchanged, wflag_carcinomaNOTkeeping, wflag_carcinomaNOTno) THEN
						0
					ELSE 1
				END) +--AS worsenChk_7,
				(CASE
					WHEN 1 IN (wflag_neoplasmNOTno, wflag_progressNOTno, wflag_deterioratNOTno, wflag_relapseNOTno,
								wflag_increaseinvolumeNOTno, wflag_effusionNOTincreaseinsize, wflag_spreadNOTno) THEN
						1
					ELSE 0
				END) +--AS worsenChk_8,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) +--AS worsenChk_9,
				(CASE
					WHEN 1 IN (wflag_diseaseANDsecondary) THEN
						1
					ELSE 0
				END) --AS worsenChk_10
			) > 0 THEN 1
			ELSE 0
		END) AS worsenChk,
		(
		CASE 
			WHEN
			(
				(CASE
					WHEN 1 IN (nwflag_stableNOTnot, nwflag_resolvANDdisease, nwflag_diseaseANDno, nwflag_noevidenceNOTconclusion, 
								nwflag_nodefiniteevidenceNOTconclusion, nwflag_nomeasurableNOTno) THEN
						1
					ELSE 0
				END) +--AS notWorsenChk_1
				(CASE
					WHEN 1 IN (nwflag_responseNOTnot, nwflag_responseNOTno)  THEN
						1
					ELSE 0
				END) --AS notWorsenChk_2
			) > 0 THEN 1
			ELSE 0
		END) AS notWorsenChk
INTO #simpleNLP_CR
FROM
(
SELECT * FROM( --t42
SELECT * FROM( --t41
SELECT * FROM( --t40
SELECT * FROM( --t39
SELECT * FROM( --t38
SELECT * FROM( --t37
SELECT * FROM( --t36
SELECT * FROM( --t35
SELECT * FROM( --t34
SELECT * FROM( --t33
SELECT * FROM( --t32
SELECT * FROM( --t31
SELECT * FROM( --t30
SELECT * FROM( --t29
SELECT * FROM( --t28
SELECT * FROM( --t27
SELECT * FROM( --t26
SELECT * FROM( --t25
SELECT * FROM( --t24
SELECT * FROM( --t23
SELECT * FROM( --t22
SELECT * FROM( --t21
SELECT * FROM( --t20
SELECT * FROM( --t19
SELECT * FROM( --t18
SELECT * FROM( --t17
SELECT * FROM( --t16
SELECT * FROM( --t15
SELECT * FROM( --t14
SELECT * FROM( --t13
SELECT * FROM( --t12
SELECT * FROM( --t11
SELECT * FROM( --t10
SELECT * FROM( --t9
SELECT * FROM( --t8
SELECT * FROM( --t7
SELECT * FROM( --t6
SELECT * FROM( --t5
SELECT * FROM( --t4
SELECT * FROM( --t3
SELECT * FROM( --t2
SELECT * FROM( --t1
SELECT key1 AS unionKey, pID1 AS unionpID, en_EventDate1 AS unionts FROM #wflag_metastNOTno -- 1
UNION ALL
SELECT key2 AS unionKey, pID2 AS unionpID, en_EventDate2 AS unionts FROM #wflag_metastNOTrather -- 2
UNION ALL
SELECT key3 AS unionKey, pID3 AS unionpID, en_EventDate3 AS unionts FROM #wflag_metastNOTstable-- 3
UNION ALL
SELECT key4 AS unionKey, pID4 AS unionpID, en_EventDate4 AS unionts FROM #wflag_metastNOTknown -- 4
UNION ALL
SELECT key5 AS unionKey, pID5 AS unionpID, en_EventDate5 AS unionts FROM #wflag_metastNOTdecrease -- 5
UNION ALL
SELECT key6 AS unionKey, pID6 AS unionpID, en_EventDate6 AS unionts FROM #wflag_recurNOTno -- 6
UNION ALL
SELECT key7 AS unionKey, pID7 AS unionpID, en_EventDate7 AS unionts FROM #wflag_malignanNOTunchanged -- 7
UNION ALL
SELECT key8 AS unionKey, pID8 AS unionpID, en_EventDate8 AS unionts FROM #wflag_malignanNOTno -- 8
UNION ALL
SELECT key9 AS unionKey, pID9 AS unionpID, en_EventDate9 AS unionts FROM #wflag_unchangedNOTmalignan -- 9
UNION ALL
SELECT key10 AS unionKey, pID10 AS unionpID, en_EventDate10 AS unionts FROM #wflag_bulkNOTreduc -- 10
UNION ALL
SELECT key11 AS unionKey, pID11 AS unionpID, en_EventDate11 AS unionts FROM #wflag_bulkNOTdecrease -- 11
UNION ALL
SELECT key12 AS unionKey, pID12 AS unionpID, en_EventDate12 AS unionts FROM #wflag_massNOTreduc -- 12
UNION ALL
SELECT key13 AS unionKey, pID13 AS unionpID, en_EventDate13 AS unionts FROM #wflag_massNOTdecrease -- 13
UNION ALL
SELECT key14 AS unionKey, pID14 AS unionpID, en_EventDate14 AS unionts FROM #wflag_diseaseNOTunchanged -- 14
UNION ALL
SELECT key15 AS unionKey, pID15 AS unionpID, en_EventDate15 AS unionts FROM #wflag_diseaseNOTstable -- 15
UNION ALL
SELECT key16 AS unionKey, pID16 AS unionpID, en_EventDate16 AS unionts FROM #wflag_resolvNOTdisease -- 16
UNION ALL
SELECT key17 AS unionKey, pID17 AS unionpID, en_EventDate17 AS unionts FROM #wflag_stableNOTdisease -- 17
UNION ALL
SELECT key18 AS unionKey, pID18 AS unionpID, en_EventDate18 AS unionts FROM #wflag_responseNOTdisease -- 18
UNION ALL
SELECT key19 AS unionKey, pID19 AS unionpID, en_EventDate19 AS unionts FROM #wflag_diseaseNOTreduc -- 19
UNION ALL
SELECT key20 AS unionKey, pID20 AS unionpID, en_EventDate20 AS unionts FROM #wflag_diseaseNOTpaget -- 20
UNION ALL
SELECT key21 AS unionKey, pID21 AS unionpID, en_EventDate21 AS unionts FROM #wflag_diseaseNOTdecrease -- 21
UNION ALL
SELECT key22 AS unionKey, pID22 AS unionpID, en_EventDate22 AS unionts FROM #wflag_diseaseNOTno -- 22
UNION ALL
SELECT key23 AS unionKey, pID23 AS unionpID, en_EventDate23 AS unionts FROM #wflag_carcinomaNOTunchanged -- 23
UNION ALL
SELECT key24 AS unionKey, pID24 AS unionpID, en_EventDate24 AS unionts FROM #wflag_carcinomaNOTkeeping -- 24
UNION ALL
SELECT key25 AS unionKey, pID25 AS unionpID, en_EventDate25 AS unionts FROM #wflag_carcinomaNOTno -- 25
UNION ALL
SELECT key26 AS unionKey, pID26 AS unionpID, en_EventDate26 AS unionts FROM #wflag_neoplasmNOTno -- 26
UNION ALL
SELECT key27 AS unionKey, pID27 AS unionpID, en_EventDate27 AS unionts FROM #wflag_progressNOTno -- 27
UNION ALL
SELECT key28 AS unionKey, pID28 AS unionpID, en_EventDate28 AS unionts FROM #wflag_deterioratNOTno -- 28
UNION ALL
SELECT key29 AS unionKey, pID29 AS unionpID, en_EventDate29 AS unionts FROM #wflag_relapseNOTno -- 29
UNION ALL
SELECT key30 AS unionKey, pID30 AS unionpID, en_EventDate30 AS unionts FROM #wflag_increaseinvolumeNOTno -- 30
UNION ALL
SELECT key31 AS unionKey, pID31 AS unionpID, en_EventDate31 AS unionts FROM #wflag_effusionNOTincreaseinsize -- 31
UNION ALL
SELECT key32 AS unionKey, pID32 AS unionpID, en_EventDate32 AS unionts FROM #wflag_spreadNOTno -- 32
UNION ALL
SELECT key33 AS unionKey, pID33 AS unionpID, en_EventDate33 AS unionts FROM #wflag_diseaseANDsecondary -- 33
UNION ALL
SELECT key34 AS unionKey, pID34 AS unionpID, en_EventDate34 AS unionts FROM #nwflag_stableNOTnot -- 34
UNION ALL
SELECT key35 AS unionKey, pID35 AS unionpID, en_EventDate35 AS unionts FROM #nwflag_resolvANDdisease -- 35
UNION ALL
SELECT key36 AS unionKey, pID36 AS unionpID, en_EventDate36 AS unionts FROM #nwflag_diseaseANDno -- 36
UNION ALL
SELECT key37 AS unionKey, pID37 AS unionpID, en_EventDate37 AS unionts FROM #nwflag_noevidenceNOTconclusion -- 37
UNION ALL
SELECT key38 AS unionKey, pID38 AS unionpID, en_EventDate38 AS unionts FROM #nwflag_nodefiniteevidenceNOTconclusion -- 38
UNION ALL
SELECT key39 AS unionKey, pID39 AS unionpID, en_EventDate39 AS unionts FROM #nwflag_nomeasurableNOTno -- 39
UNION ALL
SELECT key40 AS unionKey, pID40 AS unionpID, en_EventDate40 AS unionts FROM #nwflag_responseNOTnot -- 40
UNION ALL
SELECT key41 AS unionKey, pID41 AS unionpID, en_EventDate41 AS unionts FROM #nwflag_responseNOTno -- 41
UNION ALL
SELECT key42 AS unionKey, pID42 AS unionpID, en_EventDate42 AS unionts FROM #mflag_responseANDmixed -- 42
) t1
LEFT OUTER JOIN
(SELECT key1, wflag_metastNOTno FROM #wflag_metastNOTno) t
ON unionKey = t.key1
) t2
LEFT OUTER JOIN
(SELECT key2, wflag_metastNOTrather FROM #wflag_metastNOTrather) t
ON unionKey = t.key2
) t3
LEFT OUTER JOIN
(SELECT key3, wflag_metastNOTstable FROM #wflag_metastNOTstable) t
ON unionKey = t.key3
) t4
LEFT OUTER JOIN
(SELECT key4, wflag_metastNOTknown FROM #wflag_metastNOTknown) t
ON unionKey = t.key4
) t5
LEFT OUTER JOIN
(SELECT key5, wflag_metastNOTdecrease FROM #wflag_metastNOTdecrease) t
ON unionKey = t.key5
) t6
LEFT OUTER JOIN
(SELECT key6, wflag_recurNOTno FROM #wflag_recurNOTno) t
ON unionKey = t.key6
) t7
LEFT OUTER JOIN
(SELECT key7, wflag_malignanNOTunchanged FROM #wflag_malignanNOTunchanged) t
ON unionKey = t.key7
) t8
LEFT OUTER JOIN
(SELECT key8, wflag_malignanNOTno FROM #wflag_malignanNOTno) t
ON unionKey = t.key8
) t9
LEFT OUTER JOIN
(SELECT key9, wflag_unchangedNOTmalignan FROM #wflag_unchangedNOTmalignan) t
ON unionKey = t.key9
) t10
LEFT OUTER JOIN
(SELECT key10, wflag_bulkNOTreduc FROM #wflag_bulkNOTreduc) t
ON unionKey = t.key10
) t11
LEFT OUTER JOIN
(SELECT key11, wflag_bulkNOTdecrease FROM #wflag_bulkNOTdecrease) t
ON unionKey = t.key11
) t12
LEFT OUTER JOIN
(SELECT key12, wflag_massNOTreduc FROM #wflag_massNOTreduc) t
ON unionKey = t.key12
) t13
LEFT OUTER JOIN
(SELECT key13, wflag_massNOTdecrease FROM #wflag_massNOTdecrease) t
ON unionKey = t.key13
) t14
LEFT OUTER JOIN
(SELECT key14, wflag_diseaseNOTunchanged FROM #wflag_diseaseNOTunchanged) t
ON unionKey = t.key14
) t15
LEFT OUTER JOIN
(SELECT key15, wflag_diseaseNOTstable FROM #wflag_diseaseNOTstable) t
ON unionKey = t.key15
) t16
LEFT OUTER JOIN
(SELECT key16, wflag_resolvNOTdisease FROM #wflag_resolvNOTdisease) t
ON unionKey = t.key16
) t17
LEFT OUTER JOIN
(SELECT key17, wflag_stableNOTdisease FROM #wflag_stableNOTdisease) t
ON unionKey = t.key17
) t18
LEFT OUTER JOIN
(SELECT key18, wflag_responseNOTdisease FROM #wflag_responseNOTdisease) t
ON unionKey = t.key18
) t19
LEFT OUTER JOIN
(SELECT key19, wflag_diseaseNOTreduc FROM #wflag_diseaseNOTreduc) t
ON unionKey = t.key19
) t20
LEFT OUTER JOIN
(SELECT key20, wflag_diseaseNOTpaget FROM #wflag_diseaseNOTpaget) t
ON unionKey = t.key20
) t21
LEFT OUTER JOIN
(SELECT key21, wflag_diseaseNOTdecrease FROM #wflag_diseaseNOTdecrease) t
ON unionKey = t.key21
) t22
LEFT OUTER JOIN
(SELECT key22, wflag_diseaseNOTno FROM #wflag_diseaseNOTno) t
ON unionKey = t.key22
) t23
LEFT OUTER JOIN
(SELECT key23, wflag_carcinomaNOTunchanged FROM #wflag_carcinomaNOTunchanged) t
ON unionKey = t.key23
) t24
LEFT OUTER JOIN
(SELECT key24, wflag_carcinomaNOTkeeping FROM #wflag_carcinomaNOTkeeping) t
ON unionKey = t.key24
) t25
LEFT OUTER JOIN
(SELECT key25, wflag_carcinomaNOTno FROM #wflag_carcinomaNOTno) t
ON unionKey = t.key25
) t26
LEFT OUTER JOIN
(SELECT key26, wflag_neoplasmNOTno FROM #wflag_neoplasmNOTno) t
ON unionKey = t.key26
) t27
LEFT OUTER JOIN
(SELECT key27, wflag_progressNOTno FROM #wflag_progressNOTno) t
ON unionKey = t.key27
) t28
LEFT OUTER JOIN
(SELECT key28, wflag_deterioratNOTno FROM #wflag_deterioratNOTno) t
ON unionKey = t.key28
) t29
LEFT OUTER JOIN
(SELECT key29, wflag_relapseNOTno FROM #wflag_relapseNOTno) t
ON unionKey = t.key29
) t30
LEFT OUTER JOIN
(SELECT key30, wflag_increaseinvolumeNOTno FROM #wflag_increaseinvolumeNOTno) t
ON unionKey = t.key30
) t31
LEFT OUTER JOIN
(SELECT key31, wflag_effusionNOTincreaseinsize FROM #wflag_effusionNOTincreaseinsize) t
ON unionKey = t.key31
) t32
LEFT OUTER JOIN
(SELECT key32, wflag_spreadNOTno FROM #wflag_spreadNOTno) t
ON unionKey = t.key32
) t33
LEFT OUTER JOIN
(SELECT key33, wflag_diseaseANDsecondary FROM #wflag_diseaseANDsecondary) t
ON unionKey = t.key33
) t34
LEFT OUTER JOIN
(SELECT key34, nwflag_stableNOTnot FROM #nwflag_stableNOTnot) t
ON unionKey = t.key34
) t35
LEFT OUTER JOIN
(SELECT key35, nwflag_resolvANDdisease FROM #nwflag_resolvANDdisease) t
ON unionKey = t.key35
) t36
LEFT OUTER JOIN
(SELECT key36, nwflag_diseaseANDno FROM #nwflag_diseaseANDno) t
ON unionKey = t.key36
) t37
LEFT OUTER JOIN
(SELECT key37, nwflag_noevidenceNOTconclusion FROM #nwflag_noevidenceNOTconclusion) t
ON unionKey = t.key37
) t38
LEFT OUTER JOIN
(SELECT key38, nwflag_nodefiniteevidenceNOTconclusion FROM #nwflag_nodefiniteevidenceNOTconclusion) t
ON unionKey = t.key38
) t39
LEFT OUTER JOIN
(SELECT key39, nwflag_nomeasurableNOTno FROM #nwflag_nomeasurableNOTno) t
ON unionKey = t.key39
) t40
LEFT OUTER JOIN
(SELECT key40, nwflag_responseNOTnot FROM #nwflag_responseNOTnot) t
ON unionKey = t.key40
) t41
LEFT OUTER JOIN
(SELECT key41, nwflag_responseNOTno FROM #nwflag_responseNOTno) t
ON unionKey = t.key41
) t42
LEFT OUTER JOIN
(SELECT key42, mflag_responseANDmixed FROM #mflag_responseANDmixed) t
ON unionKey = t.key42
) t43
-- ** Change NULL to zero. **
begin --
UPDATE #simpleNLP_CR SET wflag_metastNOTno = 0 WHERE wflag_metastNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_metastNOTrather = 0 WHERE wflag_metastNOTrather IS NULL
UPDATE #simpleNLP_CR SET wflag_metastNOTstable = 0 WHERE wflag_metastNOTstable IS NULL
UPDATE #simpleNLP_CR SET wflag_metastNOTknown = 0 WHERE wflag_metastNOTknown IS NULL
UPDATE #simpleNLP_CR SET wflag_metastNOTdecrease = 0 WHERE wflag_metastNOTdecrease IS NULL
UPDATE #simpleNLP_CR SET wflag_recurNOTno = 0 WHERE wflag_recurNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_malignanNOTunchanged = 0 WHERE wflag_malignanNOTunchanged IS NULL
UPDATE #simpleNLP_CR SET wflag_malignanNOTno = 0 WHERE wflag_malignanNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_unchangedNOTmalignan = 0 WHERE wflag_unchangedNOTmalignan IS NULL
UPDATE #simpleNLP_CR SET wflag_bulkNOTreduc = 0 WHERE wflag_bulkNOTreduc IS NULL
UPDATE #simpleNLP_CR SET wflag_bulkNOTdecrease = 0 WHERE wflag_bulkNOTdecrease IS NULL
UPDATE #simpleNLP_CR SET wflag_massNOTreduc = 0 WHERE wflag_massNOTreduc IS NULL
UPDATE #simpleNLP_CR SET wflag_massNOTdecrease = 0 WHERE wflag_massNOTdecrease IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTunchanged = 0 WHERE wflag_diseaseNOTunchanged IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTstable = 0 WHERE wflag_diseaseNOTstable IS NULL
UPDATE #simpleNLP_CR SET wflag_resolvNOTdisease = 0 WHERE wflag_resolvNOTdisease IS NULL
UPDATE #simpleNLP_CR SET wflag_stableNOTdisease = 0 WHERE wflag_stableNOTdisease IS NULL
UPDATE #simpleNLP_CR SET wflag_responseNOTdisease = 0 WHERE wflag_responseNOTdisease IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTreduc = 0 WHERE wflag_diseaseNOTreduc IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTpaget = 0 WHERE wflag_diseaseNOTpaget IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTdecrease = 0 WHERE wflag_diseaseNOTdecrease IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseNOTno = 0 WHERE wflag_diseaseNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_carcinomaNOTunchanged = 0 WHERE wflag_carcinomaNOTunchanged IS NULL
UPDATE #simpleNLP_CR SET wflag_carcinomaNOTkeeping = 0 WHERE wflag_carcinomaNOTkeeping IS NULL
UPDATE #simpleNLP_CR SET wflag_carcinomaNOTno = 0 WHERE wflag_carcinomaNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_neoplasmNOTno = 0 WHERE wflag_neoplasmNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_progressNOTno = 0 WHERE wflag_progressNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_deterioratNOTno = 0 WHERE wflag_deterioratNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_relapseNOTno = 0 WHERE wflag_relapseNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_increaseinvolumeNOTno = 0 WHERE wflag_increaseinvolumeNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_effusionNOTincreaseinsize = 0 WHERE wflag_effusionNOTincreaseinsize IS NULL
UPDATE #simpleNLP_CR SET wflag_spreadNOTno = 0 WHERE wflag_spreadNOTno IS NULL
UPDATE #simpleNLP_CR SET wflag_diseaseANDsecondary = 0 WHERE wflag_diseaseANDsecondary IS NULL
UPDATE #simpleNLP_CR SET nwflag_stableNOTnot = 0 WHERE nwflag_stableNOTnot IS NULL
UPDATE #simpleNLP_CR SET nwflag_resolvANDdisease = 0 WHERE nwflag_resolvANDdisease IS NULL
UPDATE #simpleNLP_CR SET nwflag_diseaseANDno = 0 WHERE nwflag_diseaseANDno IS NULL
UPDATE #simpleNLP_CR SET nwflag_noevidenceNOTconclusion = 0 WHERE nwflag_noevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_CR SET nwflag_nodefiniteevidenceNOTconclusion = 0 WHERE nwflag_nodefiniteevidenceNOTconclusion IS NULL
UPDATE #simpleNLP_CR SET nwflag_nomeasurableNOTno = 0 WHERE nwflag_nomeasurableNOTno IS NULL
UPDATE #simpleNLP_CR SET nwflag_responseNOTnot = 0 WHERE nwflag_responseNOTnot IS NULL
UPDATE #simpleNLP_CR SET nwflag_responseNOTno = 0 WHERE nwflag_responseNOTno IS NULL
UPDATE #simpleNLP_CR SET mixedChk = 0 WHERE mixedChk IS NULL
end --


END