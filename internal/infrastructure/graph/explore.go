package graph

import (
	"context"
	"fmt"

	"github.com/neo4j/neo4j-go-driver/v5/neo4j"
)

// NodeView is a generic, serialisable view of a graph node used by the
// graph exploration endpoints (GET /graph/nodes).
type NodeView struct {
	ID         string                 `json:"id"`
	Label      string                 `json:"label"`
	Type       string                 `json:"type"`
	Properties map[string]interface{} `json:"properties"`
}

// RelationView is a generic, serialisable view of a graph relationship used
// by the graph exploration endpoints (GET /graph/relations).
type RelationView struct {
	ID         string                 `json:"id"`
	From       string                 `json:"from"`
	To         string                 `json:"to"`
	Type       string                 `json:"type"`
	Properties map[string]interface{} `json:"properties"`
}

// cypherListNodes returns nodes of any label with optional label filter and
// free-text search over the common display properties (value, name, id).
// Nodes with a last_seen property sort first (most recent activity).
const cypherListNodes = `
MATCH (n)
WHERE ($type = '' OR any(l IN labels(n) WHERE toLower(l) = toLower($type)))
  AND ($search = '' OR
       toLower(coalesce(toString(n.value), '')) CONTAINS toLower($search) OR
       toLower(coalesce(toString(n.name), '')) CONTAINS toLower($search) OR
       toLower(coalesce(toString(n.id), '')) CONTAINS toLower($search))
RETURN n
ORDER BY coalesce(n.last_seen, 0) DESC
LIMIT $limit`

// cypherListRelations returns relationships with optional relationship-type
// filter, endpoint node filter, and free-text search over endpoint display
// properties.
const cypherListRelations = `
MATCH (a)-[r]->(b)
WHERE ($type = '' OR toLower(type(r)) = toLower($type))
  AND ($node_id = '' OR
       coalesce(toString(a.id), '') = $node_id OR
       coalesce(toString(b.id), '') = $node_id OR
       elementId(a) = $node_id OR
       elementId(b) = $node_id)
  AND ($search = '' OR
       toLower(coalesce(toString(a.value), toString(a.name), '')) CONTAINS toLower($search) OR
       toLower(coalesce(toString(b.value), toString(b.name), '')) CONTAINS toLower($search))
RETURN elementId(r) AS id,
       type(r) AS type,
       properties(r) AS props,
       coalesce(toString(a.id), elementId(a)) AS from_id,
       coalesce(toString(b.id), elementId(b)) AS to_id
LIMIT $limit`

// ListNodes returns graph nodes, optionally filtered by label (case
// insensitive) and a free-text search over value/name/id properties.
func (r *GraphRepository) ListNodes(ctx context.Context, nodeType, search string, limit int) ([]NodeView, error) {
	params := map[string]interface{}{
		"type":   nodeType,
		"search": search,
		"limit":  limit,
	}

	result, err := r.client.ExecuteRead(ctx, func(tx neo4j.ManagedTransaction) (interface{}, error) {
		res, err := tx.Run(ctx, cypherListNodes, params)
		if err != nil {
			return nil, err
		}

		nodes := make([]NodeView, 0)
		for res.Next(ctx) {
			raw, ok := res.Record().Get("n")
			if !ok {
				continue
			}
			node, ok := raw.(neo4j.Node)
			if !ok {
				continue
			}
			nodes = append(nodes, nodeToView(node))
		}
		return nodes, res.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list graph nodes: %w", err)
	}

	return result.([]NodeView), nil
}

// ListRelations returns graph relationships, optionally filtered by
// relationship type, an endpoint node id, and a free-text search over the
// endpoints' display properties.
func (r *GraphRepository) ListRelations(ctx context.Context, relType, nodeID, search string, limit int) ([]RelationView, error) {
	params := map[string]interface{}{
		"type":    relType,
		"node_id": nodeID,
		"search":  search,
		"limit":   limit,
	}

	result, err := r.client.ExecuteRead(ctx, func(tx neo4j.ManagedTransaction) (interface{}, error) {
		res, err := tx.Run(ctx, cypherListRelations, params)
		if err != nil {
			return nil, err
		}

		relations := make([]RelationView, 0)
		for res.Next(ctx) {
			record := res.Record()

			view := RelationView{
				ID:         recordString(record, "id"),
				Type:       recordString(record, "type"),
				From:       recordString(record, "from_id"),
				To:         recordString(record, "to_id"),
				Properties: map[string]interface{}{},
			}

			if raw, ok := record.Get("props"); ok {
				if props, ok := raw.(map[string]interface{}); ok && props != nil {
					view.Properties = props
				}
			}

			relations = append(relations, view)
		}
		return relations, res.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list graph relations: %w", err)
	}

	return result.([]RelationView), nil
}

// nodeToView converts a Neo4j node to the generic NodeView shape used by the
// exploration endpoints.
func nodeToView(node neo4j.Node) NodeView {
	props := node.Props
	if props == nil {
		props = map[string]interface{}{}
	}

	id := propString(props, "id")
	if id == "" {
		id = node.ElementId
	}

	nodeType := ""
	if len(node.Labels) > 0 {
		nodeType = node.Labels[0]
	}

	label := firstNonEmptyString(
		propString(props, "value"),
		propString(props, "name"),
		propString(props, "technique_id"),
		id,
	)

	return NodeView{
		ID:         id,
		Label:      label,
		Type:       nodeType,
		Properties: props,
	}
}

// propString extracts a string property, returning "" for missing or
// non-string values.
func propString(props map[string]interface{}, key string) string {
	if raw, ok := props[key]; ok {
		if s, ok := raw.(string); ok {
			return s
		}
	}
	return ""
}

// recordString extracts a string value from a record key, returning "" for
// missing or non-string values.
func recordString(record *neo4j.Record, key string) string {
	if raw, ok := record.Get(key); ok {
		if s, ok := raw.(string); ok {
			return s
		}
	}
	return ""
}

// firstNonEmptyString returns the first non-empty string of the candidates.
func firstNonEmptyString(candidates ...string) string {
	for _, c := range candidates {
		if c != "" {
			return c
		}
	}
	return ""
}
