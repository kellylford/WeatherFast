"""Standalone single-alert sheet (iOS AlertDetailView parity).

Opened from any place that shows an alert row - currently the detailed view's
ALERTS section - so the alert's full text is always one Enter away.
"""

import wx

from ..accessible_list import AccessibleLinesPanel
from ..alert_format import detail_lines


class AlertDetailDialog(wx.Dialog):
    def __init__(self, parent, alert):
        super().__init__(parent, title=f"Weather Alert - {alert.event}", size=(700, 560))
        self.alert = alert

        panel = wx.Panel(self)
        vbox = wx.BoxSizer(wx.VERTICAL)

        self.lines = AccessibleLinesPanel(panel)
        self.lines.set_lines(detail_lines(alert))
        vbox.Add(self.lines, 1, wx.EXPAND | wx.ALL, 8)

        row = wx.BoxSizer(wx.HORIZONTAL)
        if alert.details_url:
            source_btn = wx.Button(panel, label=f"View on {alert.source} Website")
            source_btn.Bind(wx.EVT_BUTTON,
                            lambda e: wx.LaunchDefaultBrowser(alert.details_url))
            row.Add(source_btn, 0, wx.RIGHT, 8)
        close_btn = wx.Button(panel, wx.ID_CLOSE, "Close")
        row.Add(close_btn, 0)
        vbox.Add(row, 0, wx.ALIGN_CENTER | wx.ALL, 8)

        panel.SetSizer(vbox)
        self.SetEscapeId(wx.ID_CLOSE)
        self.Bind(wx.EVT_BUTTON, lambda e: self.EndModal(wx.ID_CLOSE), id=wx.ID_CLOSE)
        wx.CallAfter(self.lines.set_focus)
