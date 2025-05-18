BEGIN TRY
	BEGIN TRANSACTION

		IF OBJECT_ID('tempdb.dbo.#PromotionDetails') IS NOT NULL DROP TABLE #PromotionDetails
		IF OBJECT_ID('tempdb.dbo.#temp_Overheadstypes') IS NOT NULL DROP TABLE #temp_Overheadstypes
		---------------------------------------------------------------------------
		
		-- Preparing Promotions Details Data --

		---------------------------------------------------------------------------
		
		Create Table #PromotionDetails
		(
			PromotionID Int, 
			DateFrom Date, 
			DateTo Date,
			MaxNumberOfTrades Int,
			PromotionPercent float,
			PromotionCap Decimal,
			Active bit,
			ClientAccPromotionID Int,
			ClientAccProfileId Int,
			PromotionsDetailId Int,
			OperationType Int,
			CompanyCode char(3) COLLATE Arabic_BIN,
			MarketId smallint
		)

		Insert Into #PromotionDetails
		Select P.PromotionID, P.DateFrom, P.DateTo, P.MaxNumberOfTrades, P.PromotionPercent,
		P.PromotionCap, P.Active, CAP.ClientAccPromotionID, CAP.ClientAccProfileId, PD.PromotionsDetailId, PD.OperationType, PD.CompanyCode, PD.MarketId
		From Promotions P
		Inner Join ClientAccPromotions CAP On CAP.PromotionID = P.PromotionID
		Inner Join PromotionsDetails PD On PD.PromotionID = P.PromotionID
		Where ((P.DateFrom Is Not Null And P.DateFrom <= GetDate()) Or P.DateFrom Is Null)
				And ((P.DateTo Is Not Null And P.DateTo >= GetDate()) Or P.DateTo Is Null)
				And P.Active = 1


		---------------------------------------------------------------------------
		
		-- Moving ClientAccOverheads for ClientAccProfileIds For Expired Promotions or Exceeded Trading and Cap Limits --
		--  To ClientAccOverheads_Backup table with active flag equal zero for tracking history of promotions --

		---------------------------------------------------------------------------

		Insert INTO [dbo].[ClientAccOverheads_Backup] 
		select DISTINCT CAOH.ClientAccProfileID
				,CAOH.OverheadID
				,CAOH.OverheadValue
				,CAOH.IsPercentage
				,CAOH.MaxValue
				,CAOH.MinValue
				,CAOH.CurrencyCode
				,CAOH.FromAmount
				,CAOH.ToAmount
				,CAOH.ClientAccOverheadID
				,CAOH.Sequence
				,CAOH.RowVer
				,CAOH.IsNegative
				,CAOH.SplitFactor
				,CAOH.Split_OverheadTypeID
				,CAOH.IsPercentageSplit
				,Null
				,0
		from ClientAccOverheads CAOH 
		inner join [ClientAccOverheads_Backup] CAOHB
		On CAOH.ClientAccOverheadID = CAOHB.NewClientAccOverheadId
		inner join ClientAccPromotions CAP
		On CAOH.ClientAccProfileID = CAP.ClientAccProfileID
		inner join Promotions P On P.PromotionId = CAP.PromotionId
		Where P.Active = 0
				Or (P.PromotionId not in (select PD.PromotionId from #PromotionDetails PD)
				Or [dbo].CalClientAccNumberOfTrades(CAOH.ClientAccProfileID) >= P.MaxNumberOfTrades
				Or [dbo].CheckClientExceededPromotionCap(CAOH.ClientAccProfileID, P.PromotionID) >= P.PromotionCap)

		---------------------------------------------------------------------------

		-- Removing ClientAccOverheads for ClientAccProfileIds For Expired Promotions or Exceeded Trading and Cap Limits --

		---------------------------------------------------------------------------

		Delete from ClientAccOverheads 
		Where ClientAccOverheadID In (Select Distinct ClientAccOverheadID from ClientAccOverheads_Backup Where Active = 0)


		---------------------------------------------------------------------------

		-- Returning original backedup ClientAccOverheads for ClientAccProfileIds For Expired Promotions --

		---------------------------------------------------------------------------

		SET IDENTITY_INSERT [ClientAccOverheads] ON
		Insert INTO [dbo].[ClientAccOverheads] (
				ClientAccProfileID
				,OverheadID
				,OverheadValue
				,IsPercentage
				,CAOHB.MaxValue
				,CAOHB.MinValue
				,CAOHB.CurrencyCode
				,FromAmount
				,ToAmount
				,ClientAccOverheadID
				,Sequence
				,RowVer
				,IsNegative
				,SplitFactor
				,Split_OverheadTypeID
				,IsPercentageSplit
		)
		select DISTINCT CAOHB.ClientAccProfileID
				,OverheadID
				,OverheadValue
				,IsPercentage
				,CAOHB.MaxValue
				,CAOHB.MinValue
				,CAOHB.CurrencyCode
				,FromAmount
				,ToAmount
				,ClientAccOverheadID
				,Sequence
				,RowVer
				,IsNegative
				,SplitFactor
				,Split_OverheadTypeID
				,IsPercentageSplit
		from [ClientAccOverheads_Backup] CAOHB
		Where Active = 1 And ClientAccOverheadID Is Not Null   
			  And NewClientAccOverheadId Not in 
				(select ClientAccOverheadID 
				from [ClientAccOverheads] where CAOHB.ClientAccProfileID = ClientAccProfileID)
		SET IDENTITY_INSERT [ClientAccOverheads] OFF

		---------------------------------------------------------------------------

		-- Deactivate original backedup ClientAccOverheads for ClientAccProfileIds For Expired Promotions --

		---------------------------------------------------------------------------

		Update [ClientAccOverheads_Backup]
		set Active = 0
		where Active = 1   
			  And NewClientAccOverheadId Not in 
				(select ClientAccOverheadID 
				from [ClientAccOverheads] where [ClientAccOverheads_Backup].ClientAccProfileID = ClientAccProfileID)


		---------------------------------------------------------------------------

		-- Taking Snapshot of the Current OverHeads Table in a Temp Table --

		---------------------------------------------------------------------------

		Create Table #temp_Overheadstypes
		(
			OverheadID int,
			OverheadValue decimal(20, 10),
			MaxValue decimal(20,10),
			MinValue decimal(20,10),
			CurrencyCode smallint,
			MarketId smallint,
			OperationTypeID Int,
			CompanyCode char(3) COLLATE Arabic_BIN
		)

		Insert Into #temp_Overheadstypes
		Select distinct [OverheadID], OverheadValue, MaxValue, MinValue, CurrencyCode, OV.MarketId, OV._OperationTypeId, OV.CompanyCode  
		from Overheads OV inner Join #PromotionDetails PD
		On OV.marketid = IsNull(PD.marketid, OV.marketid) and OV.companycode = IsNull(PD.companycode, OV.companycode)
		and OV._OperationTypeID & PD.OperationType in (1, 2)
		Where IsActive = 1 and _OverheadTypeID = 1

		---------------------------------------------------------------------------

		-- Making Backup from ClientAccOverheads for ClientAccProfilsIds with no prior ClientAccOverheads --

		---------------------------------------------------------------------------

		Insert INTO [ClientAccOverheads_Backup]			
		select 	DISTINCT ClientAccProfileID
				,TOV.OverheadID
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,null
				,Null
				,1	
		from #PromotionDetails PD
		Cross Join #temp_overheadstypes TOV
		Where Not Exists (
			select 1
			from ClientAccOverheads
			where ClientAccProfileID = PD.ClientAccProfileID and OverHeadId = TOV.OverHeadId
		)
		
		---------------------------------------------------------------------------

		-- Making Backup from ClientAccOverheads for ClientAccProfilsIds with prior ClientAccOverheads --

		---------------------------------------------------------------------------

		Insert INTO [dbo].[ClientAccOverheads_Backup]
		select DISTINCT CAOH.ClientAccProfileID
				,CAOH.OverheadID
				,CAOH.OverheadValue
				,IsPercentage
				,CAOH.MaxValue
				,CAOH.MinValue
				,CAOH.CurrencyCode
				,FromAmount
				,ToAmount
				,ClientAccOverheadID
				,Sequence
				,RowVer
				,IsNegative
				,SplitFactor
				,Split_OverheadTypeID
				,IsPercentageSplit
				,Null
				,1
		from #PromotionDetails PD
			CROSS JOIN  #temp_Overheadstypes TOH
			inner join ClientAccOverheads CAOH
			on PD.ClientAccProfileId = CAOH.ClientAccProfileId And TOH.OverHeadId = CAOH.OverHeadId
			where Not EXISTS (
				select 1
				from [ClientAccOverheads_Backup]
				where ClientAccProfileID = CAOH.ClientAccProfileID and OverHeadId = CAOH.OverHeadId
				And NewClientAccOverheadId = CAOH.ClientAccOverheadID
			)
			
		---------------------------------------------------------------------------

		-- Deleting Special OverHeads from ClientAccOverheads Table --

		---------------------------------------------------------------------------

		Delete CAOH From ClientAccOverheads as CAOH
		where ClientAccProfileId in 
		(select distinct ClientAccProfileId from ClientAccOverheads_Backup 
		where Active = 1 and CAOH.OverheadID = OverHeadId
		And NewClientAccOverheadId Is Null)

		---------------------------------------------------------------------------

		-- Inserting Special OverHeads with Promotions Discount in ClientAccOverheads Table --

		---------------------------------------------------------------------------

		Insert Into ClientAccOverheads (
			[ClientAccProfileID] ,
			[OverheadID],
			[OverheadValue],
			[IsPercentage],
			[MaxValue],
			[MinValue],
			[CurrencyCode],
			[FromAmount],
			[ToAmount],
			[IsNegative],
			[ClientAccOverheadID]
			 )
		SELECT distinct PD.clientaccprofileid,
						TOH.overheadid,
						(100 - PromotionPercent) / 100.0 * TOH.OverheadValue as [OverheadValue],
						1 as [IsPercentage],
						TOH.maxvalue [MaxValue],
						(100 - PromotionPercent) / 100.0 * TOH.MinValue as [MinValue],
						TOH.currencycode,
						0 [FromAmount],
						0 [ToAmount],
						0 [IsNegative],
						(dense_rank() OVER( ORDER BY PD.clientaccprofileid, TOH.overheadid)
						+ dbo.Getsequence('ClientAccOverheads', 0))  as [ClientAccOverheadID]
		FROM   #PromotionDetails PD
			   CROSS JOIN #temp_overheadstypes TOH
			   inner Join ClientAccOverheads_Backup CAOHB 
			   On CAOHB.ClientAccProfileid = PD.ClientAccProfileid And CAOHB.OverHeadId = TOH.OverHeadId
			   And CAOHB.NewClientAccOverheadId Is Null

		---------------------------------------------------------------------------

		-- Setting NewClientAccOverheadId In ClientAccOverheads_Backup With ClientAccOverheadId In ClientAccOverheads --

		---------------------------------------------------------------------------

		update ClientAccOverheads_Backup 
		set NewClientAccOverheadId = (
				Select ClientAccOverheadId 
				From ClientAccOverheads 
				Where clientaccprofileid = ClientAccOverheads_Backup.clientaccprofileid 
					And OverHeadId =  ClientAccOverheads_Backup.OverHeadId
					And ClientAccOverheads_Backup.Active = 1
			)
		where Active = 1 And NewClientAccOverheadId Is Null
		
	COMMIT TRANSACTION
END TRY
BEGIN CATCH
		DECLARE 
			@ErrorMessage NVARCHAR(4000),
			@ErrorSeverity INT,
			@ErrorState INT;
		SELECT 
			@ErrorMessage = ERROR_MESSAGE(),
			@ErrorSeverity = ERROR_SEVERITY(),
			@ErrorState = ERROR_STATE();
		RAISERROR (
			@ErrorMessage,
			@ErrorSeverity,
			@ErrorState    
			);
		ROLLBACK TRANSACTION
		THROW;
END CATCH
