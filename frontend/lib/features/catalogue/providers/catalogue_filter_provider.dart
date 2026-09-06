import 'package:flutter_riverpod/flutter_riverpod.dart';

class CatalogueFilterState {
  final String searchQuery;
  final String selectedCategory;

  const CatalogueFilterState({
    this.searchQuery = '',
    this.selectedCategory = 'filter_all',
  });

  CatalogueFilterState copyWith({
    String? searchQuery,
    String? selectedCategory,
  }) {
    return CatalogueFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
    );
  }
}

class CatalogueFilterNotifier extends StateNotifier<CatalogueFilterState> {
  CatalogueFilterNotifier() : super(const CatalogueFilterState());

  void setFilter({String? query, String? category}) {
    state = state.copyWith(
      searchQuery: query,
      selectedCategory: category ?? state.selectedCategory,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedCategory(String category) {
    state = state.copyWith(selectedCategory: category);
  }

  void clearFilter() {
    state = const CatalogueFilterState();
  }
}

final catalogueFilterProvider =
    StateNotifierProvider<CatalogueFilterNotifier, CatalogueFilterState>((ref) {
  return CatalogueFilterNotifier();
});
