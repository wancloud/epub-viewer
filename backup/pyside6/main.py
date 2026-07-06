import sys

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication

from epubviewer.ui.main_window import MainWindow


def main() -> int:
    app = QApplication(sys.argv)
    app.setOrganizationName("EpubViewer")
    app.setApplicationName("EpubViewer")

    window = MainWindow()
    window.show()
    QTimer.singleShot(0, window.restore_last_session)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
