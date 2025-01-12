<?php

namespace BookStack\Entities\Repos;

use BookStack\Activity\ActivityType;
use BookStack\Entities\Models\Book;
use BookStack\Entities\Models\Chapter;
use BookStack\Entities\Queries\EntityQueries;
use BookStack\Entities\Tools\BookContents;
use BookStack\Entities\Tools\TrashCan;
use BookStack\Exceptions\MoveOperationException;
use BookStack\Exceptions\PermissionsException;
use BookStack\Facades\Activity;
use Exception;

class ChapterRepo
{
    public function __construct(
        protected BaseRepo $baseRepo,
        protected EntityQueries $entityQueries,
        protected TrashCan $trashCan,
    ) {
    }

    /**
     * Create a new chapter in the system.
     */
    public function create(array $input, Book $parentBook): Chapter
    {
        $chapter = new Chapter();
        $chapter->book_id = $parentBook->id;
        $chapter->parent_chapter_id = $input['parent_chapter_id'] ?? null;
        $chapter->priority = (new BookContents($parentBook))->getLastPriority() + 1;
        $this->baseRepo->create($chapter, $input);
    
        return $chapter;
    }

    /**
     * Update the given chapter.
     */
    public function update(Chapter $chapter, array $input): Chapter
    {
        $this->baseRepo->update($chapter, $input);

        if (array_key_exists('default_template_id', $input)) {
            $this->baseRepo->updateDefaultTemplate($chapter, intval($input['default_template_id']));
        }

        Activity::add(ActivityType::CHAPTER_UPDATE, $chapter);

        return $chapter;
    }

    /**
     * Remove a chapter from the system.
     *
     * @throws Exception
     */
    public function destroy(Chapter $chapter)
    {
        $this->trashCan->softDestroyChapter($chapter);
        Activity::add(ActivityType::CHAPTER_DELETE, $chapter);
        $this->trashCan->autoClearOld();
    }

    /**
     * Move the given chapter into a new parent book.
     * The $parentIdentifier must be a string of the following format:
     * 'book:<id>' (book:5).
     *
     * @throws MoveOperationException
     * @throws PermissionsException
     */
    public function move(Chapter $chapter, string $parentIdentifier): Book
    {
        $parent = $this->entityQueries->findVisibleByStringIdentifier($parentIdentifier);
    
        if ($parent instanceof Book) {
            // --- Move the chapter under a book (existing logic) ---
            if (!userCan('chapter-create', $parent)) {
                throw new PermissionsException('User does not have permission to create a chapter within the chosen book');
            }
    
            $chapter->changeBook($parent->id);
            // Clear any existing parent_chapter_id
            $chapter->parent_chapter_id = null;
            $chapter->priority = (new BookContents($parent))->getLastPriority() + 1;
            $chapter->save();
    
            $chapter->rebuildPermissions();
            Activity::add(ActivityType::CHAPTER_MOVE, $chapter);
    
            return $parent;
        }
        elseif ($parent instanceof Chapter) {
            // --- Move the chapter under another chapter (new logic) ---
            // Check if the user can create a sub-chapter under the parent chapter
            if (!userCan('chapter-create', $parent)) {
                throw new PermissionsException('User does not have permission to create a chapter under the chosen chapter');
            }
    
            // Ensure we move it into the same book as the parent chapter
            $chapter->changeBook($parent->book_id);
            // Set the parent chapter
            $chapter->parent_chapter_id = $parent->id;
    
            // Optionally, set a priority for ordering under the parent chapter
            // You may want your own logic here:
            $maxPriority = $parent->childChapters()->max('priority') ?? 0;
            $chapter->priority = $maxPriority + 1;
            $chapter->save();
    
            $chapter->rebuildPermissions();
            Activity::add(ActivityType::CHAPTER_MOVE, $chapter);
    
            // Return the book in which the sub-chapter is now placed
            return $parent->book;
        }
        else {
            // Not a book or a chapter
            throw new MoveOperationException('Could not find a valid parent Book or Chapter to move into');
        }
    }
    
    
}
