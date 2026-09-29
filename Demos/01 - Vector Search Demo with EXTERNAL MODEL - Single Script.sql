/*
My goal is to show the pieces of vector searches:
* getting an embedding
* show storing the data in the table
* do a search
*/

USE SongLyrics
GO

/* Step 1 : Make sure the database is configured properly */
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

EXEC sp_configure 'external rest endpoint enabled', 1
RECONFIGURE


/* Step 2 : Create the connection to the local model using EXTERNAL MODEL

I used Anthony Nocentino's blog to create this model running locally in a 
docker container on my local machine.  

*/

CREATE EXTERNAL MODEL ollama
WITH (
    LOCATION = 'https://model-web:443/api/embed',
    API_FORMAT = 'Ollama',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'nomic-embed-text'
);
GO


/* Let's run a test to confirm this works */
PRINT 'Testing the external model by calling AI_GENERATE_EMBEDDINGS function...';
GO
BEGIN
    DECLARE @result NVARCHAR(MAX);
    SET @result = (SELECT CONVERT(NVARCHAR(MAX), AI_GENERATE_EMBEDDINGS(N'test text' USE MODEL ollama)))
    SELECT AI_GENERATE_EMBEDDINGS(N'test text' USE MODEL ollama) AS GeneratedEmbedding

    IF @result IS NOT NULL
        PRINT 'Model test successful. Result: ' + @result;
    ELSE
        PRINT 'Model test failed. No result returned.';
END;
GO



/* Step 3: Save Embeddings to their own table 

The recommondation is that you save the embeddings to their own table. 
Reasons why include:
* the time it takes to call the model to generate the embedding, especially if
    the model is in Azure ($$$) or if you have a lot of data to process.
* the data type we're storing the embeddings in is a vector data type. 
    Under the covers, this is a binary data type which has space and 
    performance issues that are better managed when on a separate table.

*/

-- I created a loop as this takes a while
-- It took about 6 hours to load almost 48K records
DECLARE @rowcount int = 100;

WHILE @rowcount > 0
BEGIN 
    insert into SongLyricEmbedding (SongLyricID, LyricEmbedding)
    SELECT TOP 100 id, 
        AI_GENERATE_EMBEDDINGS(Lyrics USE MODEL ollama) AS GeneratedEmbedding
    FROM SongLyric 
    WHERE id NOT IN (SELECT SongLyricID FROM SongLyricEmbedding)

    SELECT @rowcount = @@ROWCOUNT
END


/* Step 4: query away! 

Update @prompt with the search criteria
*/

/*****************************************************

WARNING: There _may_ be some NSFW lyrics out there. 
Excuse me as I "clutch my pearls..."

*****************************************************/

DECLARE @prompt nvarchar(max), 
    @vector vector(768);

SELECT @prompt = 'Shape of My Heart'   

SELECT @vector = (SELECT CONVERT(NVARCHAR(MAX), AI_GENERATE_EMBEDDINGS(@prompt USE MODEL ollama)))
SELECT @vector as Embedding

SELECT TOP 25
    lyrics.ID, lyrics.Title, lyrics.Artist, lyrics.Features, 
    lyrics.[Language], lyrics.tag,
    lyrics.Lyrics, embedding.LyricEmbedding,
    VECTOR_DISTANCE('cosine', embedding.LyricEmbedding, @vector) as distance 
FROM SongLyric as lyrics 
    JOIN SongLyricEmbedding as embedding ON lyrics.id = embedding.SongLyricID
--where tag = 'country'
--where [language] <> 'en'
ORDER BY distance;

GO

---- find similar songs
DECLARE @prompt nvarchar(max), @title nvarchar(255),
    @vector vector(768);

SELECT @prompt = Lyrics,
    @title = title
FROM SongLyric as lyrics 
where artist = 'Backstreet Boys'
order by views asc

SELECT @vector = (SELECT CONVERT(NVARCHAR(MAX), AI_GENERATE_EMBEDDINGS(@prompt USE MODEL ollama)))
SELECT @title as SongTitle, @vector as Embedding

SELECT TOP 25
    lyrics.ID, lyrics.Title, lyrics.Artist, lyrics.Features, 
    lyrics.[Language], lyrics.tag,
    lyrics.Lyrics, embedding.LyricEmbedding,
    VECTOR_DISTANCE('cosine', embedding.LyricEmbedding, @vector) as distance 
FROM SongLyric as lyrics 
    JOIN SongLyricEmbedding as embedding ON lyrics.id = embedding.SongLyricID
ORDER BY distance;

GO
