<?php

namespace BookStack\Entities;

use BookStack\Entities\Models\Book;
use BookStack\Entities\Models\Chapter;
use BookStack\Entities\Tools\ShelfContext;
use Illuminate\View\View;

class BreadcrumbsViewComposer
{
    public function __construct(
        protected ShelfContext $shelfContext
    ) {
    }

    /**
     * Modify data when the view is composed.
     */
    public function compose(View $view): void
    {
        $crumbs = $view->getData()['crumbs'];
        $firstCrumb = $crumbs[0] ?? null;

        // If first crumb is a book, check if there's a shelf context
        if ($firstCrumb instanceof Book) {
            $shelf = $this->shelfContext->getContextualShelfForBook($firstCrumb);
            if ($shelf) {
                array_unshift($crumbs, $shelf);
            }
        }

        // Build our new crumb array which includes all parent chapters
        $finalCrumbs = [];
        foreach ($crumbs as $crumb) {
            // If crumb is a Chapter, gather all of its parent chapters first
            if ($crumb instanceof Chapter) {
                $parentChain = $this->getChapterParents($crumb);
                // Insert the parent chain before the actual chapter
                foreach ($parentChain as $parent) {
                    // Avoid duplicates if you accidentally already have the parent in the list
                    if (!in_array($parent, $finalCrumbs, true)) {
                        $finalCrumbs[] = $parent;
                    }
                }
                $finalCrumbs[] = $crumb;
            } else {
                // Otherwise, just push the crumb as-is
                $finalCrumbs[] = $crumb;
            }
        }

        // Make our updated crumb list available to the view
        $view->with('crumbs', $finalCrumbs);
    }

    /**
     * Recursively collect all parent chapters up the chain.
     */
    protected function getChapterParents(Chapter $chapter): array
    {
        $parents = [];
        $current = $chapter;
        while ($current->parentChapter) {
            // Prepend each parent so that top-most parents end up first
            array_unshift($parents, $current->parentChapter);
            $current = $current->parentChapter;
        }

        return $parents;
    }
}
