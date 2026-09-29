/* https://github.com/Azure-Samples/azure-sql-db-vector-search */


/*
My goal is to show the pieces of vector searches:
* getting an embedding
* show storing the data in the table
* do a search
*/


/******************************************/
/* Step 1: Enable external REST endpoints */
USE master;
GO
sp_configure 'external rest endpoint enabled', 1;
GO
RECONFIGURE WITH OVERRIDE;
GO


/******************************************/
/* Step 2: Make sure we can use vector searches.  */

/* Old way: (pre RC1) */ 
/* Make sure that the trace flags are on */
--DBCC TRACEON (466, 13981, -1) 
--GO

/* New Way: */

-- Step 0: Enable Preview Feature
ALTER DATABASE SCOPED CONFIGURATION
SET PREVIEW_FEATURES = ON;
GO
SELECT * FROM sys.database_scoped_configurations WHERE [name] = 'PREVIEW_FEATURES'
GO



/******************************************/
/* Step 3: Set up database credentials */ 

Use AdventureWorks
GO

/* Master Key */
if not exists(select * from sys.symmetric_keys where [name] = '##MS_DatabaseMasterKey##')
begin
    create master key encryption by password = N'DebsStupidlyStr0ngP@ssword';
end
go


/* Database Scoped Credential */
if exists(select * from sys.[database_scoped_credentials] where name = 'https://debaihub9242215391.openai.azure.com')
begin
	drop database scoped credential [https://debaihub9242215391.openai.azure.com];
end

create database scoped credential [https://debaihub9242215391.openai.azure.com]
with identity = 'HTTPEndpointHeaders', secret = '{"api-key": "<api-key>"}';
go




/************************************************/
/* call the API to my AzureAI */
DECLARE @retval int, 
	@response nvarchar(max),
	@vector vector(1536);

-- This is the text to get the embedding for:
DECLARE @search nvarchar(max) = 'Find me low budget bikes';
DECLARE @payload nvarchar(max) = json_object('input': @search);

-- The url for the LLM
DECLARE @url nvarchar(1000) 
	= 'https://debaihub9242215391.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15'

EXEC @retval = sp_invoke_external_rest_endpoint
	@url = @url,
	@method = 'POST',
	@credential = [https://debaihub9242215391.openai.azure.com],
	@payload = @payload,
	@response = @response output;

-- Get just the embeddings from the response
SELECT @vector = cast(json_query(@response, '$.result.data[0].embedding') as vector(1536));
SELECT @vector as SearchEmbedding






/************************************************/
/*
Now for a real world example. Let's do a search in our AdventureWorks databases against that search criteria.
Let's look at our descriptions:
*/
SELECT p.Name as ProductName, pm.Name as ProductModelName, pd.Description, map.CultureID
FROM Production.ProductModelProductDescriptionCulture as map
	JOIN Production.ProductModel as pm ON map.ProductModelID = pm.ProductModelID
	JOIN Production.ProductDescription as pd ON map.ProductDescriptionID = pd.ProductDescriptionID
	JOIN Production.Product as p ON p.ProductModelID = pm.ProductModelID
ORDER BY p.Name, pm.Name 



















/************************************************/
-- I could get embeddings for each of these. But there's a better way to do this.
-- Let's store the embeddings for each of the descriptions.
-- Recommendation from Microsoft - store embeddings in a different table 



DROP TABLE IF EXISTS Production.ProductDescriptionEmbeddings;
GO
CREATE TABLE Production.ProductDescriptionEmbeddings
( 
  ProductDescEmbeddingID INT IDENTITY NOT NULL PRIMARY KEY CLUSTERED, -- Need a single column as cl index to support vector index reqs
  ProductID INT NOT NULL,
  ProductDescriptionID INT NOT NULL,
  ProductModelID INT NOT NULL,
  CultureID nchar(6) NOT NULL,
  Embedding vector(1536)
);
-- Populate rows without embeddings
-- Need to make sure and only get Products that have ProductModels
INSERT INTO Production.ProductDescriptionEmbeddings
SELECT p.ProductID, pmpdc.ProductDescriptionID, pmpdc.ProductModelID, pmpdc.CultureID, NULL
FROM Production.ProductModelProductDescriptionCulture pmpdc
JOIN Production.Product p
ON pmpdc.ProductModelID = p.ProductModelID
ORDER BY p.ProductID;
GO

-- Create an alternate key using an ncl index
CREATE UNIQUE NONCLUSTERED INDEX [IX_ProductDescriptionEmbeddings_AlternateKey]
ON [Production].[ProductDescriptionEmbeddings]
(
    [ProductID] ASC,
    [ProductModelID] ASC,
    [ProductDescriptionID] ASC,
    [CultureID] ASC
);
GO




/******************************************/
/* Step 5: Popoulate Embeddings table */


CREATE OR ALTER PROCEDURE [get_embedding]
    @inputText nvarchar(max),
    @embedding vector(1536) output
as

/* Modified from: https://github.com/Azure-Samples/azure-sql-db-vector-search/blob/main/Embeddings/T-SQL/02-create-get-embedding-procedure.sql */
begin try

    declare @retval int;
    declare @payload nvarchar(max) = json_object('input': @inputText);
    declare @response nvarchar(max)

    declare @url nvarchar(1000) = 'https://debaihub9242215391.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15'

    exec @retval = sp_invoke_external_rest_endpoint
        @url = @url,
        @method = 'POST',
        @credential = [https://debaihub9242215391.openai.azure.com],
        @payload = @payload,
        @response = @response output;

end try
begin catch
    select 
        'SQL' as error_source, 
        error_number() as error_code,
        error_message() as error_message
    return;
end catch

if (@retval != 0) begin
    select 
        'OPENAI' as error_source, 
        json_value(@response, '$.result.error.code') as error_code,
        json_value(@response, '$.result.error.message') as error_message,
        @response as error_response
    return;
end;

set @embedding = cast(json_query(@response, '$.result.data[0].embedding') as vector(1536))

return @retval
GO


/* update the table */
DECLARE @ProductName NVARCHAR(50);
DECLARE @ProductModelName NVARCHAR(50);
DECLARE @Description NVARCHAR(400);
DECLARE @ProductID INT;
DECLARE @ProductModelID INT;
DECLARE @ProductDescriptionID INT;
DECLARE @CultureID NCHAR(6);
DECLARE @vector vector(1536);
DECLARE @text nvarchar(max);
DECLARE @i INT = 1;


DECLARE ProductCursor CURSOR FOR
SELECT p.Name, pm.Name, pd.Description, pde.ProductID, pde.ProductModelID, pde.ProductDescriptionID, pde.CultureID
FROM Production.ProductDescription pd
JOIN Production.ProductDescriptionEmbeddings pde
    ON pd.ProductDescriptionID = pde.ProductDescriptionID
JOIN Production.Product p
    ON p.ProductID = pde.ProductID
JOIN Production.ProductModel pm
    ON pm.ProductModelID = p.ProductModelID

OPEN ProductCursor;

FETCH NEXT FROM ProductCursor INTO @ProductName, @ProductModelName, @Description, @ProductID, @ProductModelID, @ProductDescriptionID, @CultureID;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Process each row here
    --SET @text = (SELECT 'Name: ' + @ProductName + 'Model: ' + @ProductModelName + ', Description: ' + @Description);
    SET @text = (SELECT 'Name: ' + @ProductName + ', Description: ' + @Description);
    
BEGIN TRAN
    EXEC get_embedding @text, @vector output;

    UPDATE Production.ProductDescriptionEmbeddings SET Embedding = @vector
    WHERE ProductID = @ProductID
    AND ProductModelID = @ProductModelID
    AND ProductDescriptionID = @ProductDescriptionID
    AND CultureID = @CultureID;
    
COMMIT TRAN;
    FETCH NEXT FROM ProductCursor INTO @ProductName, @ProductModelName, @Description, @ProductID, @ProductModelID, @ProductDescriptionID, @CultureID;
    PRINT @i;

    if @i % 50 = 0
	BEGIN
       WAITFOR DELAY '00:1:00'; -- wait for 1 minute, every 50 items (to allow for OpenAI API rate limiting)
    END

    SET @i = @i + 1;
END


CLOSE ProductCursor;
DEALLOCATE ProductCursor;


-- takes about 40 minutes to complete


/******************************************/
/* Look at the results */
SELECT p.Name as ProductName, pm.Name as ProductModelName, pd.Description, 
	map.CultureID, pde.Embedding 
FROM Production.ProductModelProductDescriptionCulture as map
	JOIN Production.ProductModel as pm ON map.ProductModelID = pm.ProductModelID
	JOIN Production.ProductDescription as pd ON map.ProductDescriptionID = pd.ProductDescriptionID
	JOIN Production.Product as p ON p.ProductModelID = pm.ProductModelID
	JOIN Production.ProductDescriptionEmbeddings as pde 
		ON pde.ProductID = p.ProductID
		AND pde.ProductDescriptionID = pd.ProductDescriptionID
		AND pde.ProductModelID = pm.ProductModelID
ORDER BY p.Name, pm.Name 













/************************************************/
/* 
Now let's bring these two things together. 
*/

/************************************************/
-- Example Query to get the distance between this embedding and the ones in the descriptions:
SELECT 
	TOP 25
    pde.ProductID, pde.ProductModelID, pde.ProductDescriptionID, pde.CultureID, 
    VECTOR_DISTANCE('cosine', pde.[Embedding], @vector) AS distance
FROM 
    Production.ProductDescriptionEmbeddings pde
ORDER BY
    distance 
;
GO













/************************************************/
/* You can turn this into a stored proc so you can easily call this multiple times.
Doing this the long way so you can see the "magic".
Run everything together with the sample query to get the results
*/

DECLARE @retval int, 
	@response nvarchar(max),
	@vector vector(1536);

-- This is the prompt to get the embedding for:
DECLARE @search nvarchar(max) = 'Find me low budget bikes';
DECLARE @payload nvarchar(max) = json_object('input': @search);

-- The url for the LLM
DECLARE @url nvarchar(1000) 
	= 'https://debaihub9242215391.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15'

EXEC @retval = sp_invoke_external_rest_endpoint
	@url = @url,
	@method = 'POST',
	@credential = [https://debaihub9242215391.openai.azure.com],
	@payload = @payload,
	@response = @response output;

-- Get just the embeddings from the response
SELECT @vector = cast(json_query(@response, '$.result.data[0].embedding') as vector(1536));

-- now get the full results
WITH embedding_cte AS (
SELECT TOP 25
    pde.ProductID, pde.ProductModelID, pde.ProductDescriptionID, pde.CultureID, 
    VECTOR_DISTANCE('cosine', pde.[Embedding], @vector) as distance
FROM Production.ProductDescriptionEmbeddings pde
ORDER BY distance 
)
SELECT p.Name as ProductName, pm.Name as ProductModelName, pd.Description, cte.CultureID
FROM Production.ProductModelProductDescriptionCulture as map
	JOIN Production.ProductModel as pm ON map.ProductModelID = pm.ProductModelID
	JOIN Production.ProductDescription as pd ON map.ProductDescriptionID = pd.ProductDescriptionID
	JOIN Production.Product as p ON p.ProductModelID = pm.ProductModelID
	JOIN embedding_cte as cte 
		ON cte.ProductID = p.ProductID
		AND cte.ProductDescriptionID = pd.ProductDescriptionID
		AND cte.ProductModelID = pm.ProductModelID;
GO



/************************************************/
/* Get the descriptions that are not in English */
DECLARE @retval int, 
	@response nvarchar(max),
	@vector vector(1536);

-- This is the prompt to get the embedding for:
DECLARE @search nvarchar(max) = 'Find me low budget bikes';
DECLARE @payload nvarchar(max) = json_object('input': @search);

-- The url for the LLM
declare @url nvarchar(1000) = 'https://debaihub9242215391.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15'
exec @retval = sp_invoke_external_rest_endpoint
	@url = @url,
	@method = 'POST',
	@credential = [https://debaihub9242215391.openai.azure.com],
	@payload = @payload,
	@response = @response output;

-- Get just the embeddings from the response
SELECT @vector = 
	cast(json_query(@response, '$.result.data[0].embedding') as vector(1536));


-- now get the full results
WITH embedding_cte as (
SELECT 
	TOP 25
    pde.ProductID, pde.ProductModelID, pde.ProductDescriptionID, pde.CultureID, 
    vector_distance('cosine', pde.[Embedding], @vector) as distance
FROM Production.ProductDescriptionEmbeddings pde
WHERE pde.CultureID <> 'en'
ORDER BY distance 
)
SELECT p.Name as ProductName, pm.Name as ProductModelName, pd.Description, 
	cte.CultureID
FROM Production.ProductModelProductDescriptionCulture as map
	JOIN Production.ProductModel as pm ON map.ProductModelID = pm.ProductModelID
	JOIN Production.ProductDescription as pd ON map.ProductDescriptionID = pd.ProductDescriptionID
	JOIN Production.Product as p ON p.ProductModelID = pm.ProductModelID
	JOIN embedding_cte as cte 
		ON cte.ProductID = p.ProductID
		AND cte.ProductDescriptionID = pd.ProductDescriptionID
		AND cte.ProductModelID = pm.ProductModelID;
GO
