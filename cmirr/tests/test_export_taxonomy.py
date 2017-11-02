# ----------------------------------------------------------------------------
# Copyright (c) 2017-, Jose Antonio Navas Molina.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file LICENSE, distributed with this software.
# ----------------------------------------------------------------------------

from unittest import TestCase, main
from types import GeneratorType

from biom import example_table, Table

from cmirr.export_taxonomy import taxonomy_exporter


class ExportTaxonomyTests(TestCase):
    def test_taxonomy_exporter(self):
        obs = taxonomy_exporter(example_table)
        self.assertIsInstance(obs, GeneratorType)
        obs = list(obs)
        exp = ["O1\tBacteria; Firmicutes\n", "O2\tBacteria; Bacteroidetes\n"]
        self.assertEqual(obs, exp)

    def test_taxonomy_exporter_error(self):
        # Create a new table without taxonomy
        table = Table(example_table.matrix_data,
                      example_table.ids('observation'), example_table.ids())
        # Since taxonomy_exporter is a generator, it doesn't execute anything
        # until you actually use the results - force that behavior by calling
        # list
        with self.assertRaises(ValueError):
            list(taxonomy_exporter(table))


if __name__ == '__main__':
    main()
