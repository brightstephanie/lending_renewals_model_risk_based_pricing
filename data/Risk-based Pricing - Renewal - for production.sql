SET DATEFIRST 1;

DECLARE @StartDate DATETIME2(0)
DECLARE @EndDate   DATETIME2(0)

SET @StartDate = '01/01/2019'
SET @EndDate   = GETDATE()--'12/31/2020'
;WITH temp AS(
SELECT 
	FB.DTE AS funded_date,
	ISNULL(PTT.[First Loan Date], PTT.[First Payment Date]) AS FirstDateEver,
    -- MAX(CAST(FB.Dte AS DATE)) OVER(PARTITION BY FB.SS ORDER BY FB.SS) AS FundedDate_Recent,
    MAX(PTT.[Last Payment Date]) OVER(PARTITION BY FB.SS ORDER BY FB.SS) AS [Last Payment Date],
	FR.[First Next Renewal Date],
	FB.Id AS TransactionId,
	FB.SS  AS SSN,
	FB.Type AS LoanType,
	PD.ID AS PaydayID,
	PD.EXTRA4 AS [Payroll Freq],
	PD.Type AS PDType,
    Rtrim(Ltrim(SUBSTRING(PD.Yearsonjob,0,patindex('%Year(s)%', PD.Yearsonjob))))  as EmploymentLength,
    PD.Bankaccountlengthmonths,
    PD.Monthsatresidence,
    PD.Salary,
	-- DATEDIFF(DAY, CONVERT(DATE,PD.DOB), GETDATE())/365 as Age,
	PD.DOB,
    -- case when DATEDIFF(DAY, CONVERT(DATE,PD.DOB), CONVERT(DATE, PD.DTE))/365>1000 then
    --         DATEDIFF(DAY, CONVERT(DATE, PD.DOB), CONVERT(DATE, PD.DTE))/365-1000 else DATEDIFF(DAY, CONVERT(DATE, PD.DOB), CONVERT(DATE, PD.DTE))/365 end AS AgeCorrected,
    FTR.RiskScore,
    FTR0030.RiskScore AS NewFTScore,
	FB.NET AS ren_loanamount,
	CASE WHEN BA.username is null AND BA1.username in ('mpd','npd') THEN 'Organic'
		 WHEN BA.username is null AND BA1.username IS NULL THEN 'Organic'
		 WHEN BA.username is not null AND ba.username in ('mpd','npd') THEN 'Organic' ELSE 'Leads' END AS AffiliateCat,
	CASE WHEN BA.username IS NULL THEN BA1.username ELSE BA.username END AS Affiliate,
	CASE WHEN ba.status IS NULL THEN BA1.status ELSE ba.status END AS bal_status,
	AF.[LeadPrice],
	lead.loanamount,
	lead.[LeadType],
	lead.[AffiliateSubId],
	AP.ID AS APPID_WO,
	AP.Email,
	LIRNLog.Date,
	LIRNLog.[AppTypeID],
	LIRNLog.[ViewContractDate],
    LIRNLog.[SignatureDate],
	[StatusID],
	APPTYPE.[AppTypeDescription],
	APPTYPE.[AppTypeAmount],
	--BA.Date AS application_date,
	FR.[First Next Renewal Id],
	PR.[First Previous Loan Id],
	PT.[Amount Paid] AS Pay_MostRecentLoan,
	FB.NET AS LoanAmount_MostRecentLoan,
    CASE WHEN CONVERT(DECIMAL, FB.NET) = 0 THEN 0 ELSE CONVERT(DECIMAL, PTP.[Amount Paid])/CONVERT(DECIMAL, FB.NET) END AS PTL,
    PTT.[Amount Paid] AS TotalPay_All,
    PTT.TotalLoanAmt,
	PTT.WOEntries,
	PTP.[Amount Paid] AS Pay_PreviousLoan,
	PR.[First Previous LoanAmt] AS LoanAmount_PreviousLoan,
	CASE WHEN PT.[Principal Paid]-FB.net - PT.[LI Amount] >=0 THEN 1 ELSE 0 END AS paid_off,  -- 1 is paid off and 0 is not
	CASE WHEN PT.[Principal Paid]-FB.net - PT.[LI Amount] >=0 THEN PT.[Principal Paid] ELSE 0 END AS paid_off_principal,
	CASE WHEN PT.[Amount Paid] = 0 AND DATEDIFF(DAY, PD.Datedue,GETDATE())>7  THEN 1 ELSE 0 END AS [Cycled_ZP],
	CASE WHEN (PT.[Amount Paid] = 0 AND DATEDIFF(DAY, PD.Datedue,GETDATE())>7) OR PT.[Amount Paid] > 0 THEN 1 ELSE 0 END AS Cycled,
	ROW_NUMBER() OVER(PARTITION BY FB.SS ORDER BY FB.ID DESC) as RN,
	COUNT(FB.SS) OVER(PARTITION BY FB.SS ORDER BY FB.SS DESC) as NumberOfLoansBefore,
	CustomerRestriction.*,
	SMSPreference.*,
	PD.Routingnum
FROM [MPD-FBDB].dbo.FB AS FB WITH(NOLOCK)
	INNER JOIN [MPD-NAT].dbo.Payday AS PD WITH(NOLOCK)
		ON FB.SS = PD.Social
	INNER JOIN Mypayday.dbo.ApplicantMapping AS AM WITH(NOLOCK)
		ON PD.Id = AM.PaydayId

	OUTER APPLY(
		SELECT 
			TOP 1 * 
		FROM [MPD-NAT].[dbo].[LIRenewalLog] AS LIRNLog 
		WHERE LIRNLog.CustID = PD.Id 
			AND (CONVERT(date,LIRNLog.SignatureDate) BETWEEN CONVERT(date,dateadd(dd,-5, FB.DTE)) AND CONVERT(date,FB.DTE))
			AND StatusID = 1 
		ORDER BY LIRNLog.ID DESC
	) LIRNLog

	LEFT JOIN [MPD-NAT].[dbo].[LIRenewalLead] lead ON lead.[LIRenewalLogID]=LIRNLog.[ID]
	LEFT JOIN [MPD-NAT].[dbo].[ApplicationType] APPTYPE ON APPTYPE.[AppTypeID]=LIRNLog.[AppTypeID]
	LEFT JOIN Mypayday.dbo.MPDSubCodes statuslist ON LIRNLog.StatusID = statuslist.MPDSubCode AND statuslist. MpdCode = 5
	LEFT JOIN Mypayday.dbo.Applicant AS AP WITH(NOLOCK)
		ON AM.ApplicantId = AP.Id --and CONVERT(DATE,AP.DTE) BETWEEN CONVERT(date,dateadd(dd,-5, FB.DTE)) AND CONVERT(date,FB.DTE) 
	LEFT JOIN Mypayday.dbo.BuyAppsLog AS BA WITH(NOLOCK)
		ON lead.BuyAppsLogID = BA.BuyAppsLogID 
	LEFT JOIN Mypayday.dbo.BuyAppsLog AS BA1 WITH(NOLOCK)
		ON BA1.applicantID = AP.ID
	LEFT JOIN Mypayday.dbo.Affiliate AS AF WITH(NOLOCK)
		ON BA.Username = AF.Username OR BA1.USERNAME=AF.USERNAME

	-- Get next renewal
	OUTER APPLY(
		SELECT TOP(1)
			CAST(F1.Dte AS DATE) AS [First Next Renewal Date]
			,F1.ID AS [First Next Renewal Id]
		FROM
			[MPD-FBDB].dbo.FB AS F1 WITH(NOLOCK)
		WHERE
			F1.Type = 'Renewal'
			AND F1.SS = FB.SS AND F1.ID >FB.ID
		ORDER BY F1.ID ASC
	) AS FR

	-- Get previous loan
	OUTER APPLY(
		SELECT TOP(1)
			CAST(F5.Dte AS DATE) AS [First Previous Loan Date]
			,F5.ID AS [First Previous Loan Id]
			,F5.net AS [First Previous LoanAmt]
		FROM
			[MPD-FBDB].dbo.FB AS F5 WITH(NOLOCK)
		WHERE
			F5.Type IN ('Renewal', 'New Loan')
			AND F5.SS = FB.SS AND F5.ID < FB.ID
		ORDER BY F5.ID DESC
	) AS PR

	-- Get payment record for renewals
	OUTER APPLY(
			SELECT 				
				SUM(CASE WHEN CHARINDEX('payment',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN 1 ELSE 0 END) [Payments Made]
				,SUM(CASE WHEN F2.Type = 'Active -> Written Off' THEN 1 ELSE 0 END) AS WOEntries
				,SUM(CASE WHEN F2.Type = 'Active -> Written Off'  THEN  CONVERT(DECIMAL(18,4),F2.net) ELSE 0 END) AS WrittenOffAmount
				,SUM(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 THEN 1 ELSE 0 END) [Payments And Reverts Made]
				,SUM(CASE WHEN CHARINDEX('revert',F2.[Type]) > 0 THEN 1 ELSE 0 END) [Reverts Made]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F2.[Type]) > 0 THEN 1 ELSE 0 END) [LI Times]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F2.[Type]) > 0 THEN CAST(F2.net AS DECIMAL(15,4)) ELSE 0 END) [LI Amount]
				,SUM(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN CAST(F2.Paidprin AS DECIMAL(15,4)) ELSE 0 END) [Principal Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN CAST(F2.Paidint AS DECIMAL(15,4)) ELSE 0 END) [Interest Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN CAST(F2.Payment AS DECIMAL(15,4)) ELSE 0 END) AS [Amount Paid]
				,MIN(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN CAST(F2.Dte AS DATE) ELSE NULL END) AS [First Payment Date]
                ,MAX(CASE WHEN CHARINDEX('pay',F2.[Type]) > 0 OR F2.[Type] = 'Return' THEN CAST(F2.Dte AS DATE) ELSE NULL END) AS [Last Payment Date]
			FROM 
				[MPD-FBDB].dbo.FB AS F2 WITH (NOLOCK) 
			WHERE 
				F2.SS = FB.SS 
				AND F2.Id < ISNULL(FR.[First Next Renewal Id], F2.Id + 1) AND F2.ID >= FB.ID
		) AS PT

    -- Get total payment of all loans
	OUTER APPLY(
			SELECT 				
				SUM(CASE WHEN CHARINDEX('payment',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN 1 ELSE 0 END) [Payments Made]
				,SUM(CASE WHEN F3.Type = 'Active -> Written Off' THEN 1 ELSE 0 END) AS WOEntries
				,SUM(CASE WHEN F3.Type = 'Active -> Written Off'  THEN  CONVERT(DECIMAL(18,4),F3.net) ELSE 0 END) AS WrittenOffAmount
				,SUM(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 THEN 1 ELSE 0 END) [Payments And Reverts Made]
				,SUM(CASE WHEN CHARINDEX('revert',F3.[Type]) > 0 THEN 1 ELSE 0 END) [Reverts Made]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F3.[Type]) > 0 THEN 1 ELSE 0 END) [LI Times]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F3.[Type]) > 0 THEN CAST(F3.net AS DECIMAL(15,4)) ELSE 0 END) [LI Amount]
				,SUM(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN CAST(F3.Paidprin AS DECIMAL(15,4)) ELSE 0 END) [Principal Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN CAST(F3.Paidint AS DECIMAL(15,4)) ELSE 0 END) [Interest Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN CAST(F3.Payment AS DECIMAL(15,4)) ELSE 0 END) AS [Amount Paid]
				,MIN(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN CAST(F3.Dte AS DATE) ELSE NULL END) AS [First Payment Date]
                ,MAX(CASE WHEN CHARINDEX('pay',F3.[Type]) > 0 OR F3.[Type] = 'Return' THEN CAST(F3.Dte AS DATE) ELSE NULL END) AS [Last Payment Date]
				,MIN(CASE WHEN F3.Type = 'New Loan' THEN CAST(F3.Dte AS DATE) ELSE NULL END) AS [First Loan Date]
                ,SUM(CASE WHEN F3.Type IN ('New Loan', 'Renewal', 'Loan Increase') THEN CONVERT(decimal, F3.NET) ELSE 0 END) AS TotalLoanAmt
			FROM 
				[MPD-FBDB].dbo.FB AS F3 WITH (NOLOCK) 
			WHERE 
				F3.SS = FB.SS 
		) AS PTT

    -- Get payment of previous loan
	OUTER APPLY(
			SELECT 				
				SUM(CASE WHEN CHARINDEX('payment',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN 1 ELSE 0 END) [Payments Made]
				,SUM(CASE WHEN F4.Type = 'Active -> Written Off' THEN 1 ELSE 0 END) AS WOEntries
				,SUM(CASE WHEN F4.Type = 'Active -> Written Off'  THEN  CONVERT(DECIMAL(18,4),F4.net) ELSE 0 END) AS WrittenOffAmount
				,SUM(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 THEN 1 ELSE 0 END) [Payments And Reverts Made]
				,SUM(CASE WHEN CHARINDEX('revert',F4.[Type]) > 0 THEN 1 ELSE 0 END) [Reverts Made]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F4.[Type]) > 0 THEN 1 ELSE 0 END) [LI Times]
				,SUM(CASE WHEN CHARINDEX('Loan Increase',F4.[Type]) > 0 THEN CAST(F4.net AS DECIMAL(15,4)) ELSE 0 END) [LI Amount]
				,SUM(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN CAST(F4.Paidprin AS DECIMAL(15,4)) ELSE 0 END) [Principal Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN CAST(F4.Paidint AS DECIMAL(15,4)) ELSE 0 END) [Interest Paid]
				,SUM(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN CAST(F4.Payment AS DECIMAL(15,4)) ELSE 0 END) AS [Amount Paid]
				,MIN(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN CAST(F4.Dte AS DATE) ELSE NULL END) AS [First Payment Date]
                ,MAX(CASE WHEN CHARINDEX('pay',F4.[Type]) > 0 OR F4.[Type] = 'Return' THEN CAST(F4.Dte AS DATE) ELSE NULL END) AS [Last Payment Date]
			FROM 
				[MPD-FBDB].dbo.FB AS F4 WITH (NOLOCK) 
			WHERE 
				F4.SS = FB.SS 
				AND F4.ID < FB.ID AND F4.Id > PR.[First Previous Loan Id]
		) AS PTP

    outer apply 
	(
		select top 1 
			StoreID,
			Riskscore,
			Response
			-- convert(xml, replace(Response, '<?xml version="1.0" encoding="utf-8" ?>' , '')) as Response_XML
		from mypayday.dbo.factortrustresponse FT with(nolock)
		where FT.applicantID = AP.ID AND FT.StoreID not in ('0030','0020')
	) FTR
                    
    OUTER APPLY 
	(
		SELECT TOP 1 
			StoreID,
			RiskScore,
			Response
			-- convert(xml, replace(Response, '<?xml version="1.0" encoding="utf-8" ?>' , '')) as Response_XML
		FROM mypayday.dbo.factortrustresponse FT with(nolock) 
		where FT.applicantID = AP.ID AND FT.StoreID='0030'
	) FTR0030

    OUTER APPLY 
	(
	SELECT TOP(1)
		BlockRenew
		,BlockSetup
		,EmailListExclude
	FROM 
  		[MPD-NAT].dbo.CustomerRestriction AS CR
	WHERE 
  		CR.Id = PD.ID
	ORDER BY 
  		CustomerRestrictionId DESC
	) CustomerRestriction

    OUTER APPLY 
	(
	SELECT TOP(1)
		MarketingPreference
		,ServicePreference
	FROM 
		Mypayday.dbo.SMSPreference
	WHERE 
		ApplicantMappingID = AM.ApplicantMappingID
	ORDER BY 
		SMSPreferenceID DESC
	) SMSPreference

WHERE 
	-- CONVERT(DATE,FB.Dte) BETWEEN @StartDate AND @EndDate
	--AND CONVERT(DATE,BA.Date) BETWEEN @StartDate AND @EndDate     --If we need customers applied and funded in the same month, this line should be uncommented.
	FB.Type IN ('New Loan', 'Renewal')
    AND PD.Type IN ('Stored')
	AND PaydayID = 19533

	-- AND PD.State NOT IN ('Arizona', 'Colorado', 'Florida', 'Kansas', 'Minnesota', 'Missouri', 'New Jersey', 'New York', 'Ohio', 'Pennsylvania', 'South Dakota', 'Virginia', 'Wisconsin')
)


SELECT 
	PaydayID,
    SSN,
	Email,
    FirstDateEver,
	GETDATE() AS FundedDate_Recent,
	[Last Payment Date] AS LastPaymentDate,
    [Payroll Freq],
    [PDType], 
	BlockRenew,
 	BlockSetup,
	EmailListExclude,
	MarketingPreference,
	ServicePreference,
	Routingnum,
	-- LoanType,
    CASE WHEN EmploymentLength IS NULL OR EmploymentLength IN ('', 'N/', 'o', '0.5', '3 1/2') THEN '3' ELSE EmploymentLength END AS EmploymentLength, 
    Bankaccountlengthmonths, 
    Monthsatresidence, 
    Salary, 
	-- case when DATEDIFF(DAY, CONVERT(DATE,DOB), GETDATE())/365>1000 then
	-- 		DATEDIFF(DAY, CONVERT(DATE, DOB), GETDATE())/365-1000 else DATEDIFF(DAY, CONVERT(DATE, DOB), GETDATE())/365 end AS Age,
	DOB,
    MAX(TotalLoanAmt) AS HistoricalLoanAmt, 
    MAX(LoanAmount_MostRecentLoan) AS PreviousLoanAmt,
    MAX(NumberOfLoansBefore) AS NumberOfLoansBefore,
	-- MAX(LoanType) AS LoanType,
	MAX(TotalPay_All) AS Pay_Historical,
    MIN(Pay_MostRecentLoan) AS Pay_Previous,
    MIN(Pay_MostRecentLoan) - MAX(LoanAmount_MostRecentLoan) AS Profit_Previous,
    MAX(TotalPay_All) - MAX(TotalLoanAmt) AS Profit_Historical,
	MAX(WOEntries) AS WOEntries_Historical,
    DATEDIFF(DAY, MIN(CONVERT(DATE, FirstDateEver)), MAX(CONVERT(DATE, [Last Payment Date]))) AS YearsWithUs,
	DATEDIFF(DAY, MAX(CONVERT(DATE, [Last Payment Date])), GETDATE()) AS [Non-Active Duration]
FROM Temp
WHERE RN = 1
GROUP BY PaydayID, SSN, Email, [Payroll Freq], [PDType], EmploymentLength, Bankaccountlengthmonths, Monthsatresidence, Salary, RiskScore, NewFTScore, FirstDateEver, [Last Payment Date], DOB,
	BlockRenew,BlockSetup,EmailListExclude,MarketingPreference,ServicePreference,Routingnum
