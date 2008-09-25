//
//  PBGitCommitController.m
//  GitX
//
//  Created by Pieter de Bie on 19-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitCommitController.h"
#import "NSFileHandleExt.h"
#import "PBChangedFile.h"

@implementation PBGitCommitController

@synthesize files, status, busy;

- (void)awakeFromNib
{
	self.busy = 0;

	[unstagedButtonCell setAction:@selector(cellClicked:)];
	[cachedButtonCell setAction:@selector(cellClicked:)];

	[self refresh:self];
	
	[unstagedFilesController setFilterPredicate:[NSPredicate predicateWithFormat:@"cached == 0"]];
	[cachedFilesController setFilterPredicate:[NSPredicate predicateWithFormat:@"cached == 1"]];
	
	[unstagedFilesController setSortDescriptors:[NSArray arrayWithObjects:
		[[NSSortDescriptor alloc] initWithKey:@"status" ascending:false],
		[[NSSortDescriptor alloc] initWithKey:@"path" ascending:true], nil]];
	[cachedFilesController setSortDescriptors:[NSArray arrayWithObject:
		[[NSSortDescriptor alloc] initWithKey:@"path" ascending:true]]];
}

- (NSArray *) linesFromNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSData *data = [userInfo valueForKey:NSFileHandleNotificationDataItem];
	if (!data)
		return NULL;
	
	NSString* string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!string)
		return NULL;
	
	// Strip trailing newline
	if ([string hasSuffix:@"\n"])
		string = [string substringToIndex:[string length]-1];
	
	NSArray *lines = [string componentsSeparatedByString:@"\n"];
	return lines;
}

- (void) refresh:(id) sender
{
	self.status = @"Refreshing index…";
	self.busy++;
	files = [NSMutableArray array];
	[repository outputInWorkdirForArguments:[NSArray arrayWithObjects:@"update-index", @"-q", @"--unmerged", @"--ignore-missing", @"--refresh", nil]];
	self.busy--;

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter]; 
	[nc removeObserver:self]; 

	// Other files
	NSArray *arguments = [NSArray arrayWithObjects:@"ls-files", @"--others", @"--exclude-standard", nil];
	NSFileHandle *handle = [repository handleInWorkDirForArguments:arguments];
	[nc addObserver:self selector:@selector(readOtherFiles:) name:NSFileHandleReadCompletionNotification object:handle]; 
	self.busy++;
	[handle readInBackgroundAndNotify];
	
	// Unstaged files
	handle = [repository handleInWorkDirForArguments:[NSArray arrayWithObject:@"diff-files"]];
	[nc addObserver:self selector:@selector(readUnstagedFiles:) name:NSFileHandleReadCompletionNotification object:handle]; 
	self.busy++;
	[handle readInBackgroundAndNotify];

	// Cached files
	handle = [repository handleInWorkDirForArguments:[NSArray arrayWithObjects:@"diff-index", @"--cached", @"HEAD", nil]];
	[nc addObserver:self selector:@selector(readCachedFiles:) name:NSFileHandleReadCompletionNotification object:handle]; 
	self.busy++;
	[handle readInBackgroundAndNotify];
	
	self.files = files;
}

- (void) doneProcessingIndex
{
	if (!--self.busy)
		self.status = @"Ready";
}

- (void) readOtherFiles:(NSNotification *)notification;
{
	NSArray *lines = [self linesFromNotification:notification];
	for (NSString *line in lines) {
		if ([line length] == 0)
			continue;
		PBChangedFile *file =[[PBChangedFile alloc] initWithPath:line andRepository:repository];
		file.status = NEW;
		file.cached = NO;
		[files addObject: file];
	}
	self.files = files;
	[self doneProcessingIndex];
}

- (void) readUnstagedFiles:(NSNotification *)notification
{
	NSArray *lines = [self linesFromNotification:notification];
	for (NSString *line in lines) {
		NSArray *components = [line componentsSeparatedByString:@"\t"];
		if ([components count] < 2)
			break;

		PBChangedFile *file = [[PBChangedFile alloc] initWithPath:[components objectAtIndex:1] andRepository:repository];
		file.status = MODIFIED;
		file.cached =NO;
		[files addObject: file];
	}
	self.files = files;
	[self doneProcessingIndex];
}

- (void) readCachedFiles:(NSNotification *)notification
{
	NSLog(@"Reading cached files!");
	NSArray *lines = [self linesFromNotification:notification];
	for (NSString *line in lines) {
		NSArray *components = [line componentsSeparatedByString:@"\t"];
		if ([components count] < 2)
			break;

		PBChangedFile *file = [[PBChangedFile alloc] initWithPath:[components objectAtIndex:1] andRepository:repository];
		file.status = MODIFIED;
		file.cached = YES;
		[files addObject: file];
	}
	self.files = files;
	[self doneProcessingIndex];
}

- (void) commitFailedBecause:(NSString *)reason
{
	self.busy--;
	self.status = [@"Commit failed: " stringByAppendingString:reason];
	[[NSAlert alertWithMessageText:@"Commit failed"
					 defaultButton:nil
				   alternateButton:nil
					   otherButton:nil
		 informativeTextWithFormat:reason] runModal];
	return;
}

- (IBAction) commit:(id) sender
{

	NSString *commitMessage = [commitMessageView string];
	if ([commitMessage length] < 3) {
		[[NSAlert alertWithMessageText:@"Commitmessage missing"
						 defaultButton:nil
					   alternateButton:nil
						   otherButton:nil
			 informativeTextWithFormat:@"Please enter a commit message before committing"] runModal];
		return;
	}

	self.busy++;
	self.status = @"Creating tree..";
	NSString *tree = [repository outputForCommand:@"write-tree"];
	if ([tree length] != 40)
		return [self commitFailedBecause:@"Could not create a tree"];

	int ret;
	NSString *commit = [repository outputForArguments:[NSArray arrayWithObjects:@"commit-tree", tree, @"-p", @"HEAD", nil]
										  inputString:commitMessage
											 retValue: &ret];

	if (ret || [commit length] != 40)
		return [self commitFailedBecause:@"Could not create a commit object"];
	
	[repository outputForArguments:[NSArray arrayWithObjects:@"update-ref", @"-m", @"Commit from GitX", @"HEAD", commit, nil]
						  retValue: &ret];
	if (ret)
		return [self commitFailedBecause:@"Could not update HEAD"];

	[[NSAlert alertWithMessageText:@"Commit succesful"
					 defaultButton:nil
				   alternateButton:nil
					   otherButton:nil
		 informativeTextWithFormat:@"Successfully created commit %@", commit] runModal];
	
	self.busy--;
	[commitMessageView setString:@""];
	[self refresh:self];
}

- (void) cellClicked:(NSCell*) sender
{
	NSTableView *tableView = (NSTableView *)[sender controlView];
	if([tableView numberOfSelectedRows] == 1)
	{
		NSUInteger selectionIndex = [[tableView selectedRowIndexes] firstIndex];
		PBChangedFile *selectedItem = [[(([tableView tag] == 0) ? unstagedFilesController : cachedFilesController) arrangedObjects] objectAtIndex:selectionIndex];
		if (selectedItem.cached == NO) {
			[selectedItem stageChanges];
			
		}
		else {
			[selectedItem unstageChanges];
		}
		[self refresh: self];
	
	}
}

- (void)tableView:(NSTableView*)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn row:(int)rowIndex
{
	[[tableColumn dataCell] setImage:[[[(([tableView tag] == 0) ? unstagedFilesController : cachedFilesController) arrangedObjects] objectAtIndex:rowIndex] icon]];
}
@end