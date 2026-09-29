# Getting Started with Vector Searches
This repository supports the "Getting Started with Vector Searches" lightning talk. Join me as I go over the basics of vector searches in SQL Server 2025! 

Original YouTube video of the presentation can be found here: https://youtu.be/uAdnL87bv4E?si=MQlO82GpFIL1zPy1

## Demos

The scripts in [Demos](Demos/) show the main steps of vector search: generating embeddings, storing them in a table, and searching for similar content. 

### Scripts using a Song Lyrics database

- [01 - Vector Search Demo with EXTERNAL MODEL - Single Script.sql](Demos/01%20-%20Vector%20Search%20Demo%20with%20EXTERNAL%20MODEL%20-%20Single%20Script.sql): Demonstrates vector search over song lyrics using a local Ollama `nomic-embed-text` model. Creates an external model, generates 768-dimensional embeddings with `AI_GENERATE_EMBEDDINGS`, stores them in a separate table in batches, and uses cosine distance to search by a prompt or find similar songs. Assumes the `SongLyrics` database, `SongLyric` and `SongLyricEmbedding` tables, and the local model endpoint are already available.
- [02 - sp_invoke_external_rest_endpoint - ollama equivalent.sql](Demos/02%20-%20sp_invoke_external_rest_endpoint%20-%20ollama%20equivalent.sql): Shows the manual REST call behind the external-model example. Calls Ollama's `/api/embed` endpoint with `sp_invoke_external_rest_endpoint`, extracts the embedding from the JSON response, and converts it to `vector(768)`. Includes notes comparing the Ollama request and response formats with Azure OpenAI. Uses the `VectorSearchTest` database and the same local model endpoint as script 01.

### Recorded demo and accompanying script using AdventureWorks and embedding model in Foundry

- [Deb The DBA Vector Search Demo.mp4](Demos/Deb%20The%20DBA%20Vector%20Search%20Demo.mp4): Demo recording that uses the **Deb The DBA Vector Search Demo - SQL 2025 RC1.sql** script below.
- [Deb The DBA Vector Search Demo - SQL 2025 RC1.sql](Demos/Deb%20The%20DBA%20Vector%20Search%20Demo%20-%20SQL%202025%20RC1.sql): Earlier demo using AdventureWorks product descriptions and Azure OpenAI's `text-embedding-ada-002` model. Walks through configuring REST access and credentials, generating and storing 1,536-dimensional embeddings, wrapping embedding generation in a `get_embedding` stored procedure, and searching with cosine distance, including an example limited to non-English descriptions.

