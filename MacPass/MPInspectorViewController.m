//
//  MPInspectorTabViewController.m
//  MacPass
//
//  Created by Michael Starke on 05.03.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPInspectorViewController.h"
#import "MPEntryViewController.h"
#import "MPOutlineViewDelegate.h"
#import "MPPasswordCreatorViewController.h"
#import "MPShadowBox.h"
#import "MPIconHelper.h"
#import "MPPopupImageView.h"
#import "MPIconSelectViewController.h"
#import "MPDocumentWindowController.h"
#import "MPOutlineViewController.h"
#import "MPOutlineViewDelegate.h"
#import "KdbLib.h"
#import "Kdb4Node.h"
#import "KdbGroup+Undo.h"
#import "KdbEntry+Undo.h"
#import "HNHGradientView.h"

enum {
  MPNotesTab,
  MPAttachmentTab
};

@interface MPInspectorViewController () {
  BOOL _visible;
}

@property (assign, nonatomic) KdbEntry *selectedEntry;
@property (assign, nonatomic) KdbGroup *selectedGroup;

@property (retain) NSPopover *activePopover;
@property (assign) IBOutlet NSButton *generatePasswordButton;
@property (nonatomic, assign) NSDate *modificationDate;
@property (nonatomic, assign) NSDate *creationDate;
@property (retain, nonatomic) NSArrayController *attachmentController;

@end

@implementation MPInspectorViewController

- (id)init {
  return [[MPInspectorViewController alloc] initWithNibName:@"InspectorView" bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _selectedEntry = nil;
    _selectedGroup = nil;
    _attachmentController = [[NSArrayController alloc] init];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_attachmentController release];
  [_activePopover release];
  [super dealloc];
}

- (void)didLoadView {
  [self.scrollContentView setAutoresizingMask:NSViewWidthSizable];
  [[self.itemImageView cell] setBackgroundStyle:NSBackgroundStyleRaised];
  [self.itemImageView setTarget:self];
  [_bottomBar setBorderType:HNHBorderTop];
  [[_infoTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
  [_attachmentTableView setDelegate:self];
  [_attachmentTableView bind:NSContentBinding toObject:_attachmentController withKeyPath:@"arrangedObjects" options:nil];
  [_attachmentTableView setHidden:YES];
 
  [_notesOrAttachmentControl setAction:@selector(_toggleInfoTab:)];
  [_notesOrAttachmentControl setTarget:self];
  [[_notesOrAttachmentControl cell] setTag:MPAttachmentTab forSegment:MPAttachmentTab];
  [[_notesOrAttachmentControl cell] setTag:MPNotesTab forSegment:MPNotesTab];
  
  [self _clearContent];
}

- (void)setupNotifications:(MPDocumentWindowController *)windowController {
  /* Register for Entry selection */
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_didChangeCurrentItem:)
                                               name:MPCurrentItemChangedNotification
                                             object:windowController];
}

- (void)_updateInfoString {
  NSDate *modificationDate;
  NSDate *creationDate;
  if(self.selectedEntry) {
    modificationDate = self.selectedEntry.lastModificationTime;
    creationDate = self.selectedEntry.creationTime;
  }
  else {
    modificationDate = self.selectedGroup.lastModificationTime;
    creationDate = self.selectedGroup.creationTime;
  }
  [self.infoTextField setStringValue:[NSString stringWithFormat:@"created: %@ modified: %@", creationDate, modificationDate]];
}

- (void)setModificationDate:(NSDate *)modificationDate {
  [self _updateInfoString];
}

- (void)setCreationDate:(NSDate *)creationDate {
  [self _updateInfoString];
}

- (void)_updateContent {
  if(self.selectedEntry) {
    [self _showEntry];
  }
  else if(self.selectedGroup) {
    [self _showGroup];
  }
  else {
    [self _clearContent];
  }
  [self _updateAttachments];
}

- (void)_showEntry {
  
  [self bind:@"modificationDate" toObject:self.selectedEntry withKeyPath:@"lastModificationTime" options:nil];
  [self bind:@"creationDate" toObject:self.selectedEntry withKeyPath:@"creationTime" options:nil];
  
  [self.itemNameTextfield bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryTitleUndoableKey options:nil];
  [self.itemImageView setImage:[MPIconHelper icon:(MPIconType)self.selectedEntry.image ]];
  [self.passwordTextField bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryPasswordUndoableKey options:nil];
  [self.usernameTextField bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryUsernameUndoableKey options:nil];
  [self.titleOrNameLabel setStringValue:NSLocalizedString(@"TITLE",@"")];
  [self.titleTextField bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryTitleUndoableKey options:nil];
  [self.URLTextField bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryUrlUndoableKey options:nil];
  [self.notesTextView bind:NSValueBinding toObject:self.selectedEntry withKeyPath:MPEntryNotesUndoableKey options:nil];
  
  [self _setInputEnabled:YES];
}

- (void)_showGroup {
  [self bind:@"modificationDate" toObject:self.selectedGroup withKeyPath:@"lastModificationTime" options:nil];
  [self bind:@"creationDate" toObject:self.selectedGroup withKeyPath:@"creationTime" options:nil];
  
  [self.itemNameTextfield bind:NSValueBinding toObject:self.selectedGroup withKeyPath:MPGroupNameUndoableKey options:nil];
  [self.itemImageView setImage:[MPIconHelper icon:(MPIconType)self.selectedGroup.image ]];
  [self.titleOrNameLabel setStringValue:NSLocalizedString(@"NAME",@"")];
  [self.titleTextField bind:NSValueBinding toObject:self.selectedGroup withKeyPath:MPGroupNameUndoableKey options:nil];
  
  // Clear other bindins
  [self.passwordTextField unbind:NSValueBinding];
  [self.usernameTextField unbind:NSValueBinding];
  [self.URLTextField unbind:NSValueBinding];
  
  // Reset Fields
  [self.passwordTextField setStringValue:@""];
  [self.usernameTextField setStringValue:@""];
  [self.URLTextField setStringValue:@""];
  [self.notesTextView setString:@""];
  
  // Reste toggle
  [self.notesOrAttachmentControl setSelected:NO forSegment:MPNotesTab];
  [self.notesOrAttachmentControl setSelected:NO forSegment:MPAttachmentTab];
  
  [self _setInputEnabled:YES];
}

- (void)_clearContent {
  
  [self _setInputEnabled:NO];
  
  [self.itemNameTextfield unbind:NSValueBinding];
  [self.passwordTextField unbind:NSValueBinding];
  [self.usernameTextField unbind:NSValueBinding];
  [self.titleTextField unbind:NSValueBinding];
  [self.URLTextField unbind:NSValueBinding];
  [self.notesTextView unbind:NSValueBinding];
  
  [self.itemNameTextfield setStringValue:NSLocalizedString(@"INSPECTOR_NO_SELECTION", @"No item selected in inspector")];
  [self.itemImageView setImage:[NSImage imageNamed:NSImageNameActionTemplate]];
  
  [self.itemNameTextfield setStringValue:@""];
  [self.passwordTextField setStringValue:@""];
  [self.usernameTextField setStringValue:@""];
  [self.titleTextField setStringValue:@""];
  [self.URLTextField setStringValue:@""];
  [self.notesTextView setString:@""];
  
}

- (void)_setInputEnabled:(BOOL)enabled {
  
  [self.itemImageView setAction: enabled ? @selector(_showImagePopup:) : NULL ];
  [self.itemImageView setEnabled:enabled];
  [self.itemNameTextfield setTextColor: enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor] ];
  [self.itemNameTextfield setEnabled:enabled];
  [self.titleTextField setEnabled:enabled];
  
  enabled &= (self.selectedEntry != nil);
  [self.passwordTextField setEnabled:enabled];
  [self.usernameTextField setEnabled:enabled];
  [self.URLTextField setEnabled:enabled];
  [self.generatePasswordButton setEnabled:enabled];
  [self.notesTextView setEditable:enabled];
  [self.notesOrAttachmentControl setEnabled:enabled forSegment:MPNotesTab];
  [self.notesOrAttachmentControl setEnabled:enabled forSegment:MPAttachmentTab];
}

- (void)_updateAttachments {
  if(self.selectedEntry) {
    if([self.selectedEntry isKindOfClass:[Kdb4Entry class]]) {
      [self.attachmentController bind:NSContentArrayBinding toObject:self.selectedEntry withKeyPath:@"binaries" options:nil];
    }
  }
  else {
    [self.attachmentController unbind:NSContentArrayBinding];
    [self.attachmentController setContent:nil];
  }
  [self.attachmentTableView setHidden:(0 == [[self.attachmentController arrangedObjects] count])];
}

#pragma mark Actions

- (void)_toggleInfoTab:(id)sender {
  NSUInteger selectedSegment = [sender selectedSegment];
  NSUInteger tab = [[sender cell] tagForSegment:selectedSegment];
  NSView *infoView = nil;
  NSView *oldView = nil;
  switch (tab) {
    case MPNotesTab:
      infoView = _notesScrollView;
      oldView = _attachmenScrollView;
      break;
    case MPAttachmentTab:
      oldView = _notesScrollView;
      infoView = _attachmenScrollView;
    default:
      break;
  }
  if([oldView superview]) {
    [oldView removeFromSuperview];
  }
  [self.scrollContentView addSubview:infoView];
  NSDictionary *views = NSDictionaryOfVariableBindings(_notesOrAttachmentControl, infoView);
  [self.scrollContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_notesOrAttachmentControl]-10-[infoView(>=100)]-10-|"
                                                                                 options:0
                                                                                 metrics:nil
                                                                                   views:views]];
  [self.scrollContentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[infoView]-10-|"
                                                                                 options:0
                                                                                 metrics:nil
                                                                                   views:views]];
  [[self view] layout];
}

- (void)_showImagePopup:(id)sender {
  [self _showPopopver:[[[MPIconSelectViewController alloc] init] autorelease]  atView:self.itemImageView onEdge:NSMinYEdge];
}

- (void)closeActivePopup:(id)sender {
  [_activePopover close];
}

- (IBAction)_popUpPasswordGenerator:(id)sender {
  [self _showPopopver:[[[MPPasswordCreatorViewController alloc] init] autorelease] atView:self.passwordTextField onEdge:NSMinYEdge];
}

- (void)_showPopopver:(NSViewController *)viewController atView:(NSView *)view onEdge:(NSRectEdge)edge {
  _activePopover = [[NSPopover alloc] init];
  _activePopover.behavior = NSPopoverBehaviorTransient;
  _activePopover.contentViewController = viewController;
  [_activePopover showRelativeToRect:NSZeroRect ofView:view preferredEdge:edge];
  _activePopover = nil;
}

#pragma mark Notificiations
- (void)_didChangeCurrentItem:(NSNotification *)notification {
  MPDocumentWindowController *sender = [notification object];
  id item = sender.currentItem;
  if(!item) {
    self.selectedGroup = nil;
    self.selectedEntry = nil;
  }
  if([item isKindOfClass:[KdbGroup class]]) {
    self.selectedEntry = nil;
    self.selectedGroup = sender.currentItem;
  }
  else if([item isKindOfClass:[KdbEntry class]]) {
    self.selectedGroup = nil;
    self.selectedEntry = sender.currentItem;
  }
  [self _updateContent];
}

#pragma mark Properties
//- (void)setSelectedEntry:(KdbEntry *)selectedEntry {
//  if(_selectedEntry != selectedEntry) {
//    _selectedEntry = selectedEntry;
//    self.showsEntry = YES;
//    [self _updateContent];
//  }
//}
//
//- (void)setSelectedGroup:(KdbGroup *)selectedGroup {
//  if(_selectedGroup != selectedGroup) {
//    _selectedGroup = selectedGroup;
//    self.showsEntry = NO;
//    [self _updateContent];
//  }
//}

#pragma mark NSTableViewDelegate
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSTableCellView *tableCellView = [tableView makeViewWithIdentifier:[tableColumn identifier] owner:tableView];
  BinaryRef *binaryRef = [self.attachmentController arrangedObjects][row];
  [tableCellView.textField bind:NSValueBinding toObject:binaryRef withKeyPath:@"key" options:nil];
  return tableCellView;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
  NSLog(@"didAddRowView");
}

@end