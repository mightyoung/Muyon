"""Read installed metadata only; never import/launch an Office engine or probe isolation."""
import hashlib
from importlib import metadata
import json
from pathlib import Path
import platform
import re
import shutil

PACKAGES = ('python-docx', 'python-pptx', 'openpyxl', 'lxml', 'et_xmlfile',
            'typing_extensions', 'Pillow', 'XlsxWriter')
NATIVE_ROOT = Path('/opt/codex/runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice')


def file_record(path, relative_path=None):
    path = Path(path)
    data = path.read_bytes()
    return dict(relative_path=str(relative_path or path), size_bytes=len(data),
                sha256=hashlib.sha256(data).hexdigest())


def distribution_record(name):
    try:
        dist = metadata.distribution(name)
    except metadata.PackageNotFoundError:
        return dict(status='not_installed')
    evidence = []
    for item in dist.files or []:
        lower = str(item).lower()
        if (Path(item).name in ('METADATA', 'RECORD', 'WHEEL', 'INSTALLER', 'direct_url.json')
                or any(token in lower for token in ('license', 'licence', 'copying', 'notice'))):
            path = Path(dist.locate_file(item))
            if path.is_file():
                evidence.append(file_record(path, item))
    gaps = ['wheel_archive_or_index_origin_unverified', 'installed_code_not_independently_authenticated',
            'transitive_and_native_distribution_obligations_not_approved']
    if not any(any(x in item['relative_path'].lower() for x in ('license', 'licence', 'copying')) for item in evidence):
        gaps.append('full_license_text_absent_from_installed_file_list')
    return dict(status='installed_metadata_only', version=dist.version,
                installation_root=str(dist.locate_file('')),
                declared_license=dist.metadata.get('License'),
                declared_license_expression=dist.metadata.get('License-Expression'),
                project_urls=dist.metadata.get_all('Project-URL') or [],
                homepage=dist.metadata.get('Home-page'),
                requires_dist=dist.metadata.get_all('Requires-Dist') or [],
                installer=dist.read_text('INSTALLER'),
                direct_url_present=dist.read_text('direct_url.json') is not None,
                evidence=sorted(evidence, key=lambda item: item['relative_path']), gaps=gaps)


def libreoffice_record():
    wrapper = shutil.which('soffice')
    result = dict(wrapper_path=wrapper, status='static_metadata_only', executed=False,
                  evidence=[], static_version_fields={}, license_component_headings=[],
                  gaps=['exact_upstream_artifact_origin_unverified', 'distribution_and_font_license_audit_incomplete'])
    if wrapper and Path(wrapper).is_file():
        result['evidence'].append(file_record(wrapper))
    if not NATIVE_ROOT.is_dir():
        result['status'] = 'native_root_not_found_in_known_location'
        return result
    result['known_native_root'] = str(NATIVE_ROOT)
    for relative in ('program/versionrc', 'program/bootstraprc', 'program/soffice', 'program/soffice.bin', 'LICENSE'):
        path = NATIVE_ROOT / relative
        if not path.is_file():
            continue
        result['evidence'].append(file_record(path))
        if relative.endswith(('versionrc', 'bootstraprc')):
            for line in path.read_text(errors='replace').splitlines():
                if '=' in line:
                    key, value = line.split('=', 1)
                    if key in ('buildid', 'ProductKey', 'ProductCode', 'UpdateID', 'Vendor'):
                        result['static_version_fields'][key] = value
        if relative == 'LICENSE':
            text = path.read_text(errors='replace')
            result['license_component_headings'] = re.findall(r'^## (.+)$', text, re.M)
            result['top_level_declared_license'] = 'MPL-2.0 plus component-specific notices; not a single-license clearance'
    return result


def collect():
    poi_roots = (Path('/usr/share/java'), Path('/opt/codex/runtimes/codex-primary-runtime/dependencies'))
    poi_jars = sorted(str(path) for root in poi_roots if root.is_dir() for path in root.rglob('*poi*.jar') if path.is_file())
    return dict(schema_version=1, platform=platform.platform(), engine_execution='not_run',
                integration_approved=False, isolation_proven=False,
                distributions={name: distribution_record(name) for name in PACKAGES},
                libreoffice=libreoffice_record(),
                poi=dict(search_roots=[str(x) for x in poi_roots], matching_jars=poi_jars,
                         status='not_found_in_scoped_roots' if not poi_jars else 'unreviewed_jars_present'),
                available_tools={name: shutil.which(name) for name in ('python3', 'soffice', 'bwrap', 'unshare', 'prlimit', 'timeout', 'java')},
                limitations=['origin_authenticity_not_verified', 'metadata_does_not_approve_license_or_isolation',
                             'no_engine_import_execution_installation_or_network', 'isolation_attempt_recorded_separately_never_retried_here'])


if __name__ == '__main__':
    print(json.dumps(collect(), sort_keys=True, indent=2))
