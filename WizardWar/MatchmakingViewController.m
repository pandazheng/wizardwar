//
//  MatchmakingViewController.m
//  WizardWar
//
//  Created by Sean Hess on 5/17/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

#import "MatchmakingViewController.h"
#import "WWDirector.h"
#import "CCScene+Layers.h"
#import "MatchLayer.h"
#import "MatchmakingTableViewController.h"
#import "UserCell.h"
#import "InviteCell.h"
#import "User.h"
#import "Invite.h"

@interface MatchmakingViewController () <MatchLayerDelegate>
@property (nonatomic, strong) CCDirectorIOS * director;

@end

@implementation MatchmakingViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void)loadView {
    [super loadView];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.title = @"Matchmaking";
    self.view.backgroundColor = [UIColor redColor];
    self.matchesTableViewController = [[MatchmakingTableViewController alloc] initWithStyle:UITableViewStylePlain];
    self.matchesTableViewController.tableView.delegate = self;
    self.matchesTableViewController.tableView.dataSource = self;
    [self.view addSubview:self.matchesTableViewController.view];
    [self.view layoutIfNeeded];
    
    self.users = [[NSMutableArray alloc] init];
    self.invites = [[NSMutableArray alloc] init];
    [self loadDataFromFirebase];
    
    // check for set nickname
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.nickname = [defaults stringForKey:@"nickname"];
    if (self.nickname == nil) {
        // nickname not set yet so prompt for it
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Nickname" message:@"" delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [av setAlertViewStyle:UIAlertViewStylePlainTextInput];
        [av show];
        av.delegate = self;
    } else {
        [self addToLobbyList];
    }
    
    // HACK CODE
    dispatch_async(dispatch_get_main_queue(), ^{
        Invite * invite = [Invite new];
        invite.invitee = @"Charlie";
        invite.inviter = @"Bad guy";
        invite.matchID = [NSString stringWithFormat:@"%i", arc4random()];
        [self joinMatch:invite playerName:@"Charlie"];
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)joinMatch:(Invite*)invite playerName:(NSString *)playerName {
    NSAssert(invite.matchID, @"No match id!");
    NSLog(@"joining match %@ with %@", invite.matchID, playerName);
    // hide the navigation bar first, so the size of this view is correct!
    
    if (!self.director) {
        self.director = [WWDirector directorWithBounds:self.view.bounds];
    }
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    MatchLayer * match = [[MatchLayer alloc] initWithMatchId:invite.matchID playerName:playerName];
    match.delegate = self;
    
    if (self.director.runningScene) {
        [self.director replaceScene:[CCScene sceneWithLayer:match]];
    }
    else {
        [self.director runWithScene:[CCScene sceneWithLayer:match]];
    }
    
    [self.navigationController pushViewController:self.director animated:YES];
    [self removeInvite:invite];
}

- (void)doneWithMatch {
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self.navigationController popViewControllerAnimated:YES];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    // [self.navigationController pushViewController:director animated:YES];
}

#pragma mark - Alert view delegate

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    self.nickname = [alertView textFieldAtIndex:0].text;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.nickname forKey:@"nickname"];
    [self addToLobbyList];
}

#pragma mark - Firebase stuff

- (void)loadDataFromFirebase
{
    self.firebaseLobby = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseIO.com/lobby"];
    
    self.firebaseInvites = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseIO.com/invites"];
    
    self.firebaseMatches = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseio.com/match"];
    
    // LOBBY
    [self.firebaseLobby observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot *snapshot) {
        User * user = [User new];
        [user setValuesForKeysWithDictionary:snapshot.value];
        // we don't want to show us in the list
        if (user.name != self.nickname) {
            [self.users addObject:user];
            [self.matchesTableViewController.tableView reloadData];
        }
    }];
    
    [self.firebaseLobby observeEventType:FEventTypeChildRemoved withBlock:^(FDataSnapshot *snapshot) {
        User * removedUser = [User new];
        [removedUser setValuesForKeysWithDictionary:snapshot.value];
        for (User * user in self.users) {
            if ([user.name isEqualToString:removedUser.name]) {
                [self.users removeObjectIdenticalTo:user];
            }
        }
        [self.matchesTableViewController.tableView reloadData];
    }];
    
    
    //INVITES
    [self.firebaseInvites observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot *snapshot) {
        Invite * invite = [Invite new];
        [invite setValuesForKeysWithDictionary:snapshot.value];
        if ([invite.invitee isEqualToString:self.nickname]) {
            [self.invites addObject:invite];
            [self.matchesTableViewController.tableView reloadData];
        }
    }];
    
    [self.firebaseInvites observeEventType:FEventTypeChildRemoved withBlock:^(FDataSnapshot *snapshot) {
        Invite * removedInvite = [Invite new];
        [removedInvite setValuesForKeysWithDictionary:snapshot.value];
        [self removeInvite:removedInvite];
    }];
}

-(void)removeInvite:(Invite*)removedInvite {
    for (Invite * invite in self.invites) {
        if ([invite.inviter isEqualToString:removedInvite.inviter]) {
            [self.invites removeObjectIdenticalTo:invite];
        }
    }
    [self.matchesTableViewController.tableView reloadData];
}

- (void)addToLobbyList
{
    User * user = [User new];
    user.name = self.nickname;
    Firebase * userNode = [self.firebaseLobby childByAppendingPath:self.nickname];
    [userNode setValue:user.toObject];
    [userNode onDisconnectRemoveValue];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return [self.invites count];
    } else {
        return [self.users count];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Invites";
    } else {
        return @"Lobby";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    if (indexPath.section == 0) {
        InviteCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        if (!cell) {
            cell = [[InviteCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        }
        
        Invite * invite = [self.invites objectAtIndex:indexPath.row];
        
        cell.textLabel.text = invite.inviter;
        return cell;
    } else {
        UserCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        if (!cell) {
            cell = [[UserCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        }
        
        User* user = [self.users objectAtIndex:indexPath.row];
        
        cell.textLabel.text = user.name;
        return cell;
    }
}

#pragma mark - Table view delegate

-(void)createInvite:(User*)user {
    Invite * invite = [Invite new];
    invite.inviter = self.nickname;
    invite.invitee = user.name;
    
    Firebase * inviteNode = [self.firebaseInvites childByAppendingPath:invite.inviteId];
    [inviteNode setValue:invite.toObject];
    [inviteNode onDisconnectRemoveValue];
        
        // listen to the created invite for acceptance
    Firebase * matchIDNode = [inviteNode childByAppendingPath:@"matchID"];
    NSLog(@"MATCH ID NODE %@", matchIDNode);
    [matchIDNode observeEventType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {
        if (snapshot.value != [NSNull null]) {
            NSLog(@"Inivite Changed %@", snapshot.value);
            // match has begun! join up
            self.matchID = snapshot.value;
            [self joinMatch:invite playerName:self.nickname];
        }
    }];
}

-(void)selectInvite:(Invite*)invite {
    // start the match!
    NSString * matchID = [NSString stringWithFormat:@"%i", arc4random()];
    invite.matchID = matchID;
    
    Firebase* inviteNode = [self.firebaseInvites childByAppendingPath:invite.inviteId];
    [inviteNode setValue:invite.toObject];
    [inviteNode onDisconnectRemoveValue];
    [self joinMatch:invite playerName:self.nickname];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        Invite * invite = [self.invites objectAtIndex:indexPath.row];
        [self selectInvite:invite];
    } else {
        User* user = [self.users objectAtIndex:indexPath.row];
        [self createInvite:user];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
