import hashlib
import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile


spec = importlib.util.spec_from_file_location(
    "install_ai_model", Path(__file__).resolve().parents[1] / "scripts/install-ai-model.py"
)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallAiModelTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.archive = self.root / "models.zip"
        self.destination = self.root / "release" / installer.MODEL
        self.files = {"manifest.json": b"manifest", "model_quint8_x86_64.onnx": b"model", "tokenizer.json": b"tokens"}
        pins = {name: (len(data), hashlib.sha256(data).hexdigest()) for name, data in self.files.items()}
        self.pins = patch.object(installer, "FILES", pins)
        self.pins.start()
        self.addCleanup(self.pins.stop)
        self.make_archive()

    def make_archive(self, files=None):
        with zipfile.ZipFile(self.archive, "w") as bundle:
            bundle.writestr(f"{installer.MODEL}/", b"")
            for name, content in (self.files if files is None else files).items():
                bundle.writestr(f"{installer.MODEL}/{name}", content)

    def test_complete_model_is_readable_and_repeated_install_is_idempotent(self):
        installer.install(self.archive, self.destination)
        original = (self.destination / "manifest.json").stat().st_ino
        installer.install(self.archive, self.destination)
        self.assertEqual((self.destination / "manifest.json").stat().st_ino, original)
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o755)
        for name, content in self.files.items():
            self.assertEqual((self.destination / name).read_bytes(), content)
            self.assertEqual(stat.S_IMODE((self.destination / name).stat().st_mode), 0o644)

    def test_checksum_failure_does_not_publish_partial_directory(self):
        self.make_archive({**self.files, "model_quint8_x86_64.onnx": b"wrong"})
        with self.assertRaisesRegex(ValueError, "Checksum"):
            installer.install(self.archive, self.destination)
        self.assertFalse(self.destination.exists())

    def test_unexpected_size_is_rejected_before_reading_payload(self):
        self.make_archive({**self.files, "model_quint8_x86_64.onnx": b""})
        with self.assertRaisesRegex(ValueError, "size"):
            installer.verify_archive(self.archive)

    def test_missing_file_is_rejected(self):
        self.make_archive({"manifest.json": b"manifest"})
        with self.assertRaisesRegex(ValueError, "three pinned"):
            installer.verify_archive(self.archive)

    def test_traversal_and_extra_secret_file_are_rejected(self):
        for name in ("../../escape", "/etc/passwd", ".env.qwen.local"):
            with self.subTest(name=name):
                self.make_archive({**self.files, name: b"unexpected"})
                with self.assertRaisesRegex(ValueError, "three pinned"):
                    installer.install(self.archive, self.destination)
                self.assertFalse(self.destination.exists())

    def test_duplicate_zip_entry_is_rejected(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.archive, "a") as bundle:
                bundle.writestr(f"{installer.MODEL}/manifest.json", b"manifest")
        with self.assertRaisesRegex(ValueError, "three pinned"):
            installer.verify_archive(self.archive)

    def test_zip_symlink_is_rejected(self):
        with zipfile.ZipFile(self.archive, "w") as bundle:
            for name, content in self.files.items():
                entry = zipfile.ZipInfo(f"{installer.MODEL}/{name}")
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                bundle.writestr(entry, content)
        with self.assertRaisesRegex(ValueError, "symlinks"):
            installer.verify_archive(self.archive)

    def test_invalid_existing_release_is_preserved_and_rejected(self):
        self.destination.mkdir(parents=True)
        (self.destination / "manifest.json").write_bytes(b"existing")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            installer.install(self.archive, self.destination)
        self.assertEqual((self.destination / "manifest.json").read_bytes(), b"existing")

    def test_empty_docker_bind_directory_is_replaced_with_complete_model(self):
        self.destination.mkdir(parents=True)
        installer.install(self.archive, self.destination)
        installer.verify_directory(self.destination)
        self.assertEqual({path.name for path in self.destination.iterdir()}, set(self.files))

    def test_existing_directory_symlink_is_not_followed(self):
        self.destination.parent.mkdir()
        self.destination.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "real directory"):
            installer.install(self.archive, self.destination)
        self.assertTrue(self.destination.is_symlink())

    def test_failed_extraction_cleans_staging_and_does_not_publish(self):
        with patch.object(installer.shutil, "copyfileobj", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                installer.install(self.archive, self.destination)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.destination.parent.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
