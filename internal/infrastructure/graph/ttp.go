package graph

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/neo4j/neo4j-go-driver/v5/neo4j"
)

// LinkActorToTechniques ensures (ThreatActor)-[:USES]->(Technique) edges exist
// for every technique ID in the list. Technique nodes are created on demand.
// Returns the number of distinct techniques linked.
func (r *GraphRepository) LinkActorToTechniques(ctx context.Context, actorID uuid.UUID, techniqueIDs []string) (int, error) {
	if len(techniqueIDs) == 0 {
		return 0, nil
	}

	cypher := `
		MATCH (a:ThreatActor {id: $actor_id})
		UNWIND $technique_ids AS tid
		MERGE (t:Technique {technique_id: tid})
		ON CREATE SET t.created_at = $now
		MERGE (a)-[r:USES]->(t)
		SET r.updated_at = $now
		RETURN count(DISTINCT t) AS linked`

	params := map[string]interface{}{
		"actor_id":      actorID.String(),
		"technique_ids": techniqueIDs,
		"now":           time.Now().Unix(),
	}

	result, err := r.client.ExecuteWrite(ctx, func(tx neo4j.ManagedTransaction) (interface{}, error) {
		records, err := tx.Run(ctx, cypher, params)
		if err != nil {
			return nil, err
		}

		linked := 0
		if records.Next(ctx) {
			if v, ok := records.Record().Get("linked"); ok {
				if n, ok := v.(int64); ok {
					linked = int(n)
				}
			}
		}

		return linked, records.Err()
	})

	if err != nil {
		return 0, fmt.Errorf("failed to link actor to techniques: %w", err)
	}

	linked, _ := result.(int)
	return linked, nil
}

// GetActorTechniques returns the MITRE technique IDs linked to a threat actor
// via (ThreatActor)-[:USES]->(Technique) edges.
func (r *GraphRepository) GetActorTechniques(ctx context.Context, actorID uuid.UUID) ([]string, error) {
	cypher := `
		MATCH (a:ThreatActor {id: $actor_id})-[:USES]->(t:Technique)
		RETURN DISTINCT t.technique_id AS technique_id
		ORDER BY technique_id`

	params := map[string]interface{}{
		"actor_id": actorID.String(),
	}

	result, err := r.client.ExecuteRead(ctx, func(tx neo4j.ManagedTransaction) (interface{}, error) {
		records, err := tx.Run(ctx, cypher, params)
		if err != nil {
			return nil, err
		}

		var techniques []string
		for records.Next(ctx) {
			if v, ok := records.Record().Get("technique_id"); ok {
				if s, ok := v.(string); ok && s != "" {
					techniques = append(techniques, s)
				}
			}
		}

		return techniques, records.Err()
	})

	if err != nil {
		return nil, fmt.Errorf("failed to get actor techniques: %w", err)
	}

	techniques, _ := result.([]string)
	return techniques, nil
}
