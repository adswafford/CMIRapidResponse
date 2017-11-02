# ----------------------------------------------------------------------------
# Copyright (c) 2017-, Jose Antonio Navas Molina.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file LICENSE, distributed with this software.
# ----------------------------------------------------------------------------


def taxonomy_exporter(biom):
    """Extracts the taxonomy stored in the biom table

    Parameters
    ----------
    biom : biom.Table
        The BIOM table

    Raises
    ------
    ValueError
        If the input table doesn't have taxonomy

    Returns
    -------
    str generator
        A string with OBS_ID\tTAXONOMY\n
    """
    obs_md = biom.metadata(axis='observation')
    if obs_md is None or 'taxonomy' not in obs_md[0]:
        raise ValueError('The given BIOM table doesn\'t have taxonomy')

    for obs_id in biom.ids('observation'):
        taxa = biom.metadata(id=obs_id, axis='observation')['taxonomy']
        yield "%s\t%s\n" % (obs_id, '; '.join(taxa))
