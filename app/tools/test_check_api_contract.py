"""Tests for the API contract gate's reading of the backend router.

The gate fails the build when the app calls a path the backend does not
serve. A route it cannot read looks the same to it as a route that is not
there, so these tests pin the forms the router is written in.

Run from app/:  python3 -m unittest discover -s tools -p "test_*.py"
"""

import unittest
from pathlib import Path

import check_api_contract as gate


def routes(go_source: str):
    """The routes the gate reads from a piece of router code."""
    return gate.parse_chi(
        go_source.splitlines(), {"router": ""}, Path("."), follow_registers=False)


def under_api(body: str) -> str:
    return 'router.Route("/api/v1", func(api chi.Router) {\n' + body + "\n})\n"


class PlainRegistrations(unittest.TestCase):
    def test_a_route_inside_a_nested_group_takes_both_prefixes(self):
        found = routes(under_api(
            'api.Route("/darkweb", func(dw chi.Router) {\n'
            '    dw.Get("/stats", h.Stats)\n'
            '    dw.Delete("/monitor/{id}", h.Remove)\n'
            "})"))

        self.assertEqual(found, {
            ("GET", "/api/v1/darkweb/stats"),
            ("DELETE", "/api/v1/darkweb/monitor/{param}"),
        })

    def test_a_route_in_a_comment_is_not_served(self):
        found = routes(under_api(
            '// api.With(mw.OptionalAdmin).Get("/old", h.Old)\n'
            'api.Get("/new", h.New)'))

        self.assertEqual(found, {("GET", "/api/v1/new")})


class RoutesBehindMiddleware(unittest.TestCase):
    """chi's `x.With(middleware).Get(...)` serves the same path as `x.Get(...)`."""

    def test_a_route_behind_one_middleware(self):
        found = routes(under_api(
            'api.With(mw.OptionalAdmin).Get("/intel/sources", h.List)'))

        self.assertEqual(found, {("GET", "/api/v1/intel/sources")})

    def test_a_route_behind_a_middleware_that_takes_arguments(self):
        found = routes(under_api(
            'api.With(mw.AdminAuth(r.config.JWT.Secret))'
            '.Patch("/intel/sources/{slug}", h.Update)'))

        self.assertEqual(found, {("PATCH", "/api/v1/intel/sources/{param}")})

    def test_a_chain_that_continues_on_the_next_line(self):
        found = routes(under_api(
            'api.Route("/darkweb", func(dw chi.Router) {\n'
            '    dw.With(mw.RateLimit(r.cache, "password-range", r.perMinute())).\n'
            '        Post("/password/range", h.PasswordRange)\n'
            '    dw.Get("/stats", h.Stats)\n'
            "})"))

        self.assertEqual(found, {
            ("POST", "/api/v1/darkweb/password/range"),
            ("GET", "/api/v1/darkweb/stats"),
        })

    def test_middleware_listed_over_several_lines(self):
        found = routes(under_api(
            'api.Route("/taxii2", func(taxii chi.Router) {\n'
            "    taxii.With(\n"
            "        mw.APIKeyAuth(r.config.JWT.Secret),\n"
            "        mw.AdminAuth(r.config.JWT.Secret), // admins only\n"
            '    ).Post("/collections/{id}/objects", h.AddObjects)\n'
            "})"))

        self.assertEqual(
            found, {("POST", "/api/v1/taxii2/collections/{param}/objects")})

    def test_a_bracket_inside_a_quoted_argument_does_not_end_the_chain(self):
        found = routes(under_api(
            'api.With(mw.Named("limit :)", `raw (`)).Get("/limited", h.Limited)'))

        self.assertEqual(found, {("GET", "/api/v1/limited")})

    def test_middleware_written_inline_keeps_the_nesting_right(self):
        found = routes(under_api(
            'api.Route("/apps", func(apps chi.Router) {\n'
            "    apps.With(func(next http.Handler) http.Handler {\n"
            "        return next\n"
            '    }).Post("/analyze", h.Analyze)\n'
            '    apps.Get("/list", h.List)\n'
            "})\n"
            'api.Get("/stats", h.Stats)'))

        self.assertEqual(found, {
            ("POST", "/api/v1/apps/analyze"),
            ("GET", "/api/v1/apps/list"),
            ("GET", "/api/v1/stats"),
        })

    def test_a_group_of_routes_behind_middleware(self):
        found = routes(under_api(
            'api.With(mw.AdminAuth(secret)).Route("/admin", func(admin chi.Router) {\n'
            '    admin.Get("/audit", h.Audit)\n'
            "})"))

        self.assertEqual(found, {("GET", "/api/v1/admin/audit")})


if __name__ == "__main__":
    unittest.main()
