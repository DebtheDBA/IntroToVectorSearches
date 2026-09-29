USE VectorSearchTest;
GO

/************************************************/
/* Manual equivalent of AI_GENERATE_EMBEDDINGS(N'test text' USE MODEL ollama)

   The 'ollama' external model (see "CREATE EXTERNAL MODEL ollama.sql") wraps
   exactly this call: sp_invoke_external_rest_endpoint POSTing to the model's
   LOCATION with an Ollama-shaped payload. This script shows the "magic"
   underneath, the same way the video demo shows the raw call before wrapping
   it in the get_embedding stored proc.
*/

DECLARE @retval int,
    @response nvarchar(max),
    @vector vector(768);   -- nomic-embed-text is 768-dim; confirm against your model

-- This is the text to get the embedding for:
DECLARE @search nvarchar(max) = N'test text';

-- Ollama's /api/embed expects {"model": "...", "input": "..."}
DECLARE @payload nvarchar(max) = json_object('model': 'nomic-embed-text', 'input': @search);

-- Same LOCATION as CREATE EXTERNAL MODEL ollama
DECLARE @url nvarchar(1000) = 'https://model-web:443/api/embed';

EXEC @retval = sp_invoke_external_rest_endpoint
    @url = @url,
    @method = 'POST',
    @payload = @payload,
    @response = @response output;
    -- no @credential — local Ollama endpoint has no auth configured

-- Ollama returns {"embeddings": [[...]]} instead of OpenAI's {"data": [{"embedding": [...]}]}
SELECT @vector = cast(json_query(@response, '$.result.embeddings[0]') as vector(768));
SELECT @vector as GeneratedEmbedding;


/************************************************/
/* Notes for comparing to the Azure OpenAI version:

   - Payload shape differs by API_FORMAT. Azure OpenAI wants {"input": "..."};
     Ollama's /api/embed wants {"model": "...", "input": "..."} — the external
     model's MODEL = value has to travel in the JSON body here, not just be
     used for endpoint routing.
   - Response path differs too: $.result.data[0].embedding (OpenAI) vs
     $.result.embeddings[0] (Ollama).
   - No credential needed since the container endpoint isn't authenticated —
     @credential is optional on sp_invoke_external_rest_endpoint.
*/

