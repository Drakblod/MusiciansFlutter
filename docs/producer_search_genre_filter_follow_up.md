# Producer Search genre filter

Producer Search has a separate Genres/Band Types dropdown and matches its
selection against profile `Styles`. Registration and Edit Profile save their
genre picker selections in `Genres`. Adding a Blues option to Producer Search
alone would therefore miss profiles tagged Blues through those forms.

A separate change should reconcile those fields in the filter, preserve
matching for legacy `Styles`, and verify that a profile with
`Genres: ['Blues']` and empty `Styles` can be found. This package leaves the
dropdown and search behavior unchanged.
