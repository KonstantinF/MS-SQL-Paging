-- Paging:
	DECLARE @PageNumber INT = 3
	DECLARE @PageSize INT = 10

----------------------------------------------------------------------------------------
/* 2012 style:
		  SELECT *
			   , TotalCount = COUNT(*) OVER()
			FROM SYS.COLUMNS
		ORDER BY NEWID()
		  OFFSET (@PageNumber - 1) * @PageSize ROWS -- Paging
	 FETCH FIRST @PageSize ROWS ONLY; -- Paging
*/
----------------------------------------------------------------------------------------
/* Old-style:
	  SELECT *
			, TotalCount = RowId + RowIdDesc -1
		FROM (
	  SELECT *
			, ROW_NUMBER() OVER ( ORDER BY Object_id ASC) AS RowId
			, ROW_NUMBER() OVER ( ORDER BY Object_id DESC) AS RowIdDesc
		FROM SYS.COLUMNS
			) X
	   WHERE RowId BETWEEN (@PageNumber - 1) * @PageSize AND (@PageNumber * @PageSize) -1
	ORDER BY RowId
*/
----------------------------------------------------------------------------------------

-- Generic Paging flow: ( style 2012 )

-- Declare Local Variables:
	DECLARE @OrderByColumn SYSNAME = 'ColName' 
	DECLARE @OrderByIsDescending BIT = 0
	DECLARE @ConditionParam1 INT = 10
	DECLARE @ConditionParam2 VARCHAR(100) = 'TestParam'
	DECLARE @ConditionParam3 DATETIMEOFFSET(7) = '01 Jan 2010 02:00:00'
	DECLARE @table_name SYSNAME = 'TableName'
	DECLARE @table_schema SYSNAME = 'dbo'

-- Prepare the dynamic sql string:
	DECLARE @stmt NVARCHAR(MAX) = 
		N'SELECT * -- Should be replaced by the original list of columns
			   , TotalCount = COUNT(*) OVER()
			FROM ' + QUOTENAME(@table_schema) + '.' + QUOTENAME(@table_name) + N'
		   WHERE 1 = 1'

-- Resolve parameters sniffing:
		 + CASE WHEN @ConditionParam1 IS NULL THEN N'' ELSE NCHAR(10) + N' AND ConditionParam1 = @ConditionParam1 ' END
		 + CASE WHEN @ConditionParam2 IS NULL THEN N'' ELSE NCHAR(10) + N' AND ConditionParam2 = @ConditionParam2 ' END
		 + CASE WHEN @ConditionParam3 IS NULL THEN N'' ELSE NCHAR(10) + N' AND ConditionParam3 = @ConditionParam3 ' END		 			

-- Resolve the Order By logic:
	;WITH OrderByColumns AS (

-- Verification: the column @OrderByColumn belongs to the table
		SELECT [COLUMN_NAME]
			 , Id = 1
		  FROM INFORMATION_SCHEMA.COLUMNS WITH (NOLOCK)
		 WHERE [TABLE_SCHEMA] = @table_schema
		   AND [TABLE_NAME]   = @table_name
		   AND [COLUMN_NAME]  = @OrderByColumn

		UNION ALL 

-- Add all PK's columns to the "ORDER BY" part
		SELECT [COLUMN_NAME]
			 , Id = 1 + ROW_NUMBER() OVER ( ORDER BY ORDINAL_POSITION )
	      FROM  INFORMATION_SCHEMA.KEY_COLUMN_USAGE WITH (NOLOCK)
	     WHERE  OBJECTPROPERTY(OBJECT_ID(constraint_name), 'IsPrimaryKey') = 1
		   AND [TABLE_SCHEMA] = @table_schema
		   AND [TABLE_NAME]   = @table_name
		   AND [COLUMN_NAME]  <> @OrderByColumn
		)  
	
	    SELECT  @stmt = @stmt 
	    	  + NCHAR(10) 
	    	  + CASE WHEN Id = MIN(Id) OVER ( ) THEN N' ORDER BY ' ELSE N', ' END
	    	  + QUOTENAME([COLUMN_NAME])
	    	  + CASE @OrderByIsDescending WHEN 1 THEN N' DESC ' ELSE N'' END 
	      FROM  OrderByColumns
	  ORDER BY  Id

-- When the table's PK list is empty - add the faked `ORDER BY` before an OFFSET
	IF @@ROWCOUNT = 0
	BEGIN
	    SELECT  @stmt = @stmt + NCHAR(10) +  N' ORDER BY NEWID()'
	END

-- Add the Paging part
	 IF @PageNumber IS NOT NULL 
	AND @PageSize  IS NOT NULL
	BEGIN
	    SELECT @stmt = @stmt 
			 + NCHAR(10) 
			 + N'OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH FIRST @PageSize ROWS ONLY;'
	END

-- Debug
	PRINT @stmt

-- Run dynamic SQL:
	EXEC SP_EXECUTESQL @stmt = @stmt
					 , @params = 
					 N'@OrderByColumn SYSNAME 
					 , @OrderByIsDescending BIT
					 , @ConditionParam1 INT 
					 , @ConditionParam2 VARCHAR(100) 
					 , @ConditionParam3 DATETIMEOFFSET(7) 
					 , @table_name SYSNAME 
					 , @table_schema SYSNAME
					 , @PageNumber INT
					 , @PageSize INT'
					 , @OrderByColumn		= @OrderByColumn		
					 , @OrderByIsDescending = @OrderByIsDescending 
					 , @ConditionParam1		= @ConditionParam1		
					 , @ConditionParam2		= @ConditionParam2		
					 , @ConditionParam3		= @ConditionParam3		
					 , @table_name			= @table_name			
					 , @table_schema		= @table_schema		
					 , @PageNumber			= @PageNumber
					 , @PageSize			= @PageSize
