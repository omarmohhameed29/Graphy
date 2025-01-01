CREATE TYPE vertex_type
	AS ENUM ('player', 'team', 'game');


CREATE TABLE vertices (
	identifier text,
	type vertex_type,
	properties Json,
	PRIMARY KEY (identifier, type)
);


CREATE TYPE edge_type
	AS ENUM (
		'plays_against',
		'shares_team',
		'plays_in', --plays in a game
		'plays_on' --plays on a team
);

CREATE TABLE edges (
	subject_identifier text,
	subject_type vertex_type,
	object_identifier text,
	object_type vertex_type,
	edge_type edge_type,
	properties json,
	PRIMARY KEY (subject_identifier,
			subject_type, 
			object_identifier, 
			object_type, 
			edge_type)
);


INSERT INTO vertices
SELECT
	game_id as identifier,
	'game'::vertex_type as type,
	json_build_object(
		'pts_home', pts_home,
		'pts_away', pts_away,
		'winning_team', CASE WHEN home_team_wins = 1 THEN home_team_id ELSE visitor_team_id end
		) as properties
FROM games;


INSERT INTO vertices
WITH teams_deduped AS (
	SELECT *, ROW_NUMBER() OVER(partition by team_id) as row_num
	FROM teams
)
SELECT
	team_id as identifier,
	'team'::vertex_type as type,
	json_build_object(
		'abbreviation', abbreviation,
		'nickname', nickname,
		'city', city,
		'arena', arena,
		'year_founded', yearfounded
	)
FROM teams_deduped
WHERE row_num = 1;



INSERT INTO vertices
WITH player_agg as (
	SELECT
	player_id,
	MAX(player_name) player_name,
	COUNT(1) as number_of_games,
	SUMM(pts) as total_points,
	ARRAY_AGG(distinct team_id) teams
FROM game_details
GROUP BY 1
)
SELECT 
	player_id as identifier,
	'player'::vertex_type as type,
	json_build_object(
		'player_name', player_name,
		'number_of_games', number_of_games,
		'total_points', total_points,
		'teams', teams
	) as properties
FROM player_agg;





INSERT INTO edges
WITH games_deduped as(
	SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, game_id) as row_num
	FROM game_details
)
SELECT
	player_id as subject_identifier,
	'player'::vertex_type subject_type,
	game_id as object_identifier,
	'game'::vertex_type object_identifier,
	'plays_in'::edge_type edge_type,
	json_build_object(
		'start_position', start_position,
		'pts', pts,
		'team_id', team_id,
		'team_abbreviation', team_abbreviation
	) AS properties
FROM games_deduped
WHERE row_num = 1;



INSERT INTO edges
WITH teams_deduped AS (
	SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, team_id) as row_num
	FROM game_details 
)
SELECT 
	player_id as subject_identifier,
	'player'::vertex_type subject_type,
	team_id as object_identifier,
	'team'::vertex_type object_identifier,
	'plays_on'::edge_type edge_type,
	json_build_object(
		'player_name', player_name,
		'team_abbreviation', team_abbreviation,
		'min', min
	) AS properties
FROM teams_deduped
WHERE row_num = 1

			'num_games', num_games,
			'subject_points', subject_points,
			'object_points', object_points
		) AS properties;
		

INSERT INTO edges
WITH teams_deduped AS (
	SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id, game_id) as row_num
	FROM game_details 
),
	filtered AS (
		SELECT *
		FROM teams_deduped
		WHERE row_num = 1
	),
	aggregated AS (
		SELECT 
			f1.player_id AS subject_player_id,
			f2.player_id AS object_player_id,
			CASE WHEN f1.team_id = f2.team_id then 'shares_team'::edge_type else 'plays_against'::edge_type end as edge_type,
			count(1) num_games,
			sum(f1.pts) AS subject_points,
			sum(f2.pts) AS object_points
		FROM filtered f1
		JOIN filtered f2
		ON f1.game_id = f2.game_id AND f1.player_name <> f2.player_name
		WHERE f1.player_id > f2.player_id
		GROUP BY 1, 2, 3
	)
	SELECT 
		subject_player_id AS subject_identifier,
		'player'::vertex_type AS subject_type,
		object_player_id AS object_identifier,
		'player'::vertex_type AS object_type,
		edge_type AS edge_type,
		json_build_object(
			'num_games', num_games,
			'subject_points', subject_points,
			'object_points', object_points
		) AS properties
	FROM aggregated

	