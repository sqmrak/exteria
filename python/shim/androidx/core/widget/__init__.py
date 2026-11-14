"""androidx.core.widget: views that exist only to nest a scroll in another one"""

from android.widget import ScrollView


class NestedScrollView(ScrollView):
    """the scroll view of the app is the only one on ios, so nesting needs no extra state"""
